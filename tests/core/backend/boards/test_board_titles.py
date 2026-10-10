"""board-titles.py against a fake `brd` on PATH: one `brd tree` in ROOT, one
JSON line on every path, {id: title} for every card at any depth."""
import json
import os
import stat
import subprocess
import sys

import pytest

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..", "core", "backend", "boards", "board-titles.py")

# Logs its argv and cwd to $CALLS, copies its stdin to $STDIN_LOG, then (unless
# $BRD_SLEEP is set, when it becomes `sleep $BRD_SLEEP`) prints $BRD_OUT and
# exits ${BRD_EXIT:-0}.
FAKE_BRD = """#!/bin/sh
echo "brd $* (cwd=$(pwd))" >> "$CALLS"
cat > "$STDIN_LOG"
if [ -n "$BRD_SLEEP" ]; then exec sleep "$BRD_SLEEP"; fi
cat "$BRD_OUT"
exit "${BRD_EXIT:-0}"
"""

EMPTY_BOARD = {"ok": True, "data": []}


@pytest.fixture
def box(tmp_path):
    bindir = tmp_path / "bin"
    bindir.mkdir()
    brd = bindir / "brd"
    brd.write_text(FAKE_BRD)
    brd.chmod(brd.stat().st_mode | stat.S_IEXEC)
    project = tmp_path / "my project"
    project.mkdir()
    calls_log = tmp_path / "calls.log"
    calls_log.write_text("")
    stdin_log = tmp_path / "stdin.log"
    stdin_log.write_text("")
    brd_out = tmp_path / "brd.out"
    box = {
        "env": {"PATH": "%s:/usr/bin:/bin" % bindir, "CALLS": str(calls_log),
                "STDIN_LOG": str(stdin_log), "BRD_OUT": str(brd_out)},
        "bin": bindir, "project": project, "calls": calls_log, "stdin": stdin_log,
        "out": brd_out, "tmp": tmp_path,
    }
    set_out(box, EMPTY_BOARD)
    return box


def set_out(box, payload):
    """What the fake brd prints: a str verbatim, anything else as JSON."""
    text = payload if isinstance(payload, str) else json.dumps(payload, ensure_ascii=False) + "\n"
    box["out"].write_text(text, encoding="utf-8")


def invoke(box, *args, stdin_text=None, extra_env=None, cwd=None):
    """Runs the helper; asserts it printed exactly one line."""
    env = dict(box["env"], **(extra_env or {}))
    feed = {"input": stdin_text} if stdin_text is not None else {"stdin": subprocess.DEVNULL}
    proc = subprocess.run([sys.executable, SCRIPT, *args], env=env, cwd=cwd, capture_output=True,
                          text=True, encoding="utf-8", timeout=60, **feed)
    assert len(proc.stdout.splitlines()) == 1, (proc.stdout, proc.stderr)
    return proc


def run(box, *args, stdin_text=None, extra_env=None, cwd=None):
    proc = invoke(box, *args, stdin_text=stdin_text, extra_env=extra_env, cwd=cwd)
    return proc.returncode, json.loads(proc.stdout)


def calls(box):
    return box["calls"].read_text().splitlines()


def files_under(path):
    """{relative path: bytes} for every file below `path`."""
    found = {}
    for dirpath, _dirs, names in os.walk(path):
        for name in names:
            full = os.path.join(dirpath, name)
            with open(full, "rb") as f:
                found[os.path.relpath(full, path)] = f.read()
    return found


def test_runs_brd_tree_once_in_root(box):
    code, out = run(box, str(box["project"]))
    assert code == 0
    assert out == {"ok": True, "titles": {}}
    assert calls(box) == ["brd tree (cwd=%s)" % box["project"].resolve()]


def test_brd_stdin_is_dev_null(box):
    code, out = run(box, str(box["project"]), stdin_text="LEAK\n")
    assert code == 0
    assert box["stdin"].read_text() == ""


def test_brd_does_not_block_on_the_helpers_open_stdin(box):
    # The helper's stdin is a pipe that never sends EOF; brd reads its own stdin
    # to the end, so it finishes only if that stdin is /dev/null.
    p = subprocess.Popen([sys.executable, SCRIPT, str(box["project"])], stdin=subprocess.PIPE,
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=box["env"])
    try:
        code = p.wait(timeout=15)
    except subprocess.TimeoutExpired:
        p.kill()
        p.wait()
        pytest.fail("brd blocked reading the helper's stdin")
    finally:
        p.stdin.close()
    lines = p.stdout.read().splitlines()
    p.stdout.close()
    p.stderr.close()
    assert code == 0
    assert [json.loads(line) for line in lines] == [{"ok": True, "titles": {}}]


def test_flattens_nested_cards_at_any_depth(box):
    set_out(box, {"ok": True, "data": [
        {"id": "m1", "title": "Milestone one", "children": [
            {"id": "s1", "title": "Story one", "children": [
                {"id": "t1", "title": "Subtask one", "children": [
                    {"id": "x1", "title": "Sub-subtask one", "children": []},
                ]},
            ]},
        ]},
        {"id": "m2", "title": "Milestone two", "children": None},
        {"id": "m3", "title": "Milestone three"},
    ]})
    code, out = run(box, str(box["project"]))
    assert code == 0
    assert out == {"ok": True, "titles": {
        "m1": "Milestone one", "s1": "Story one", "t1": "Subtask one",
        "x1": "Sub-subtask one", "m2": "Milestone two", "m3": "Milestone three",
    }}


def test_drops_descriptions_and_every_other_field(box):
    def card(card_id, title, children):
        return {"id": card_id, "title": title, "description": "SECRET DESCRIPTION " + card_id,
                "status": "todo", "blocked_by": ["zz"], "blockers": ["yy"],
                "created_at": "2026-10-01T00:00:00Z", "updated_at": "2026-10-02T00:00:00Z",
                "children": children}
    set_out(box, {"ok": True, "data": [card("m1", "Milestone", [card("s1", "Story", [])])]})
    proc = invoke(box, str(box["project"]))
    assert proc.returncode == 0
    assert json.loads(proc.stdout) == {"ok": True, "titles": {"m1": "Milestone", "s1": "Story"}}
    for gone in ("SECRET", "description", "status", "blocked_by", "blockers",
                 "created_at", "updated_at", "children", "todo", "2026-10-0"):
        assert gone not in proc.stdout


def test_empty_board_gives_empty_titles(box):
    set_out(box, {"ok": True, "data": []})
    code, out = run(box, str(box["project"]))
    assert code == 0
    assert out == {"ok": True, "titles": {}}


def test_non_ascii_titles_round_trip(box):
    set_out(box, {"ok": True, "data": [{"id": "m1", "title": "Café — 日本", "children": []}]})
    code, out = run(box, str(box["project"]))
    assert code == 0
    assert out == {"ok": True, "titles": {"m1": "Café — 日本"}}


def test_repeated_id_keeps_the_last_in_pre_order(box):
    # Pre-order: m1, its child d, then m2, then m2's child d -- the last d wins.
    set_out(box, {"ok": True, "data": [
        {"id": "m1", "title": "First", "children": [{"id": "d", "title": "under m1", "children": []}]},
        {"id": "m2", "title": "Second", "children": [{"id": "d", "title": "under m2", "children": []}]},
    ]})
    code, out = run(box, str(box["project"]))
    assert code == 0
    assert out["titles"]["d"] == "under m2"


def test_brd_stderr_is_ignored(box):
    set_out(box, {"ok": True, "data": [{"id": "m1", "title": "One", "children": []}]})
    noisy = box["bin"] / "brd"
    noisy.write_text(FAKE_BRD.replace("#!/bin/sh\n", "#!/bin/sh\necho 'warning: something' >&2\n"))
    code, out = run(box, str(box["project"]))
    assert code == 0
    assert out == {"ok": True, "titles": {"m1": "One"}}


def test_relative_root_is_resolved_against_the_helpers_cwd(box):
    code, out = run(box, "my project", cwd=str(box["tmp"]))
    assert code == 0
    assert out == {"ok": True, "titles": {}}
    assert calls(box) == ["brd tree (cwd=%s)" % box["project"].resolve()]


def test_brd_missing(box):
    empty = box["tmp"] / "empty"
    empty.mkdir()
    code, out = run(box, str(box["project"]), extra_env={"PATH": str(empty)})
    assert code == 1
    assert out["ok"] is False
    assert out["error"]["type"] == "BrdMissing"
    assert out["error"]["message"]


@pytest.mark.parametrize("which", ["nonexistent", "regular file"])
def test_root_missing(box, which):
    root = box["tmp"] / "nope"
    if which == "regular file":
        root.write_text("not a directory")
    code, out = run(box, str(root))
    assert code == 1
    assert out["ok"] is False
    assert out["error"]["type"] == "RootMissing"
    assert str(root) in out["error"]["message"]
    assert calls(box) == []


@pytest.mark.parametrize("args", [[], ["a", "b"], [""], ["--help"]], ids=["none", "two", "empty", "dash"])
def test_usage(box, args):
    code, out = run(box, *args)
    assert code == 2
    assert out == {"ok": False, "error": {"type": "Usage", "message": "usage: board-titles.py ROOT"}}
    assert calls(box) == []


def test_never_writes(box):
    (box["project"] / "README").write_text("keep me")
    set_out(box, {"ok": True, "data": [{"id": "m1", "title": "One", "children": []}]})
    before = files_under(box["tmp"])
    code, out = run(box, str(box["project"]))
    assert code == 0
    after = files_under(box["tmp"])
    logs = {"calls.log", "stdin.log"}
    assert set(after) == set(before)
    assert {k: v for k, v in after.items() if k not in logs} == {k: v for k, v in before.items() if k not in logs}
    assert calls(box) == ["brd tree (cwd=%s)" % box["project"].resolve()]


NOT_FOUND = {"ok": False, "error": {"type": "ProjectNotFoundError",
                                    "message": "no registered project at or above /x; run `brd init` there"}}


def test_brd_envelope_is_passed_through_unchanged(box):
    set_out(box, NOT_FOUND)
    code, out = run(box, str(box["project"]), extra_env={"BRD_EXIT": "1"})
    assert code == 1
    assert out == NOT_FOUND


def test_brd_envelope_passthrough_ignores_brd_exit_code(box):
    set_out(box, NOT_FOUND)
    code, out = run(box, str(box["project"]), extra_env={"BRD_EXIT": "0"})
    assert code == 1
    assert out == NOT_FOUND


BAD_OUTPUTS = {
    "not json": "garbage <<>> output\n",
    "empty stdout": "",
    "json list": "[1, 2]\n",
    "json null": "null\n",
    "no ok": {"data": []},
    "ok string true": {"ok": "true", "data": []},
    "ok one": {"ok": 1, "data": []},
    "data missing": {"ok": True},
    "data object": {"ok": True, "data": {}},
    "card is a string": {"ok": True, "data": ["m1"]},
    "card without id": {"ok": True, "data": [{"title": "No id", "children": []}]},
    "id is a number": {"ok": True, "data": [{"id": 5, "title": "Five", "children": []}]},
    "id empty": {"ok": True, "data": [{"id": "", "title": "Blank", "children": []}]},
    "title null": {"ok": True, "data": [{"id": "m1", "title": None, "children": []}]},
    "title missing": {"ok": True, "data": [{"id": "m1", "children": []}]},
    "children object two levels down": {"ok": True, "data": [
        {"id": "m1", "title": "M", "children": [
            {"id": "s1", "title": "S", "children": [
                {"id": "t1", "title": "T", "children": {}},
            ]},
        ]},
    ]},
}


@pytest.mark.parametrize("name", list(BAD_OUTPUTS))
def test_bad_output(box, name):
    set_out(box, BAD_OUTPUTS[name])
    code, out = run(box, str(box["project"]))
    assert code == 1
    assert out["ok"] is False
    assert out["error"]["type"] == "BrdBadOutput"
    assert out["error"]["message"]
    assert "garbage" not in out["error"]["message"]
    assert "titles" not in out


def test_ok_envelope_with_nonzero_exit_is_bad_output(box):
    set_out(box, {"ok": True, "data": [{"id": "m1", "title": "One", "children": []}]})
    code, out = run(box, str(box["project"]), extra_env={"BRD_EXIT": "3"})
    assert code == 1
    assert out["ok"] is False
    assert out["error"]["type"] == "BrdBadOutput"
    assert out["error"]["message"]


def test_empty_title_is_kept(box):
    set_out(box, {"ok": True, "data": [{"id": "m1", "title": "", "children": []}]})
    code, out = run(box, str(box["project"]))
    assert code == 0
    assert out == {"ok": True, "titles": {"m1": ""}}
