"""notify.py: a desktop alert through notify-send, one JSON line on every path.

Hermetic: a temp bin dir is the WHOLE PATH (no /usr/bin, no /bin), so the real
notify-send can never run. The stub notify-send there logs its argv to
FAKE_NOTIFY_DIR/calls.log and behaves as the fixtures in FAKE_NOTIFY_DIR say.
"""
import json
import os
import stat
import subprocess
import sys

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..", "..", "..")
SCRIPT = os.path.join(ROOT, "core", "backend", "runs", "notify.py")

# The stub appends its argv (a JSON list) to calls.log, writes
# FAKE_NOTIFY_DIR/err to stderr if present (as bytes, so it may be invalid
# UTF-8), prints "stdout noise", sleeps FAKE_NOTIFY_DIR/sleep seconds if present
# and exits with FAKE_NOTIFY_DIR/code (default 0). Its shebang is the absolute
# interpreter: `env python3` would not resolve on a PATH that is only bin/.
STUB = '''#!@PYTHON@
import json, os, sys, time
d = os.environ["FAKE_NOTIFY_DIR"]
with open(os.path.join(d, "calls.log"), "a") as f:
    f.write(json.dumps(sys.argv[1:]) + "\\n")
err = os.path.join(d, "err")
if os.path.exists(err):
    with open(err, "rb") as f:
        sys.stderr.buffer.write(f.read())
    sys.stderr.flush()
sys.stdout.write("stdout noise\\n")
sys.stdout.flush()
sleep = os.path.join(d, "sleep")
if os.path.exists(sleep):
    time.sleep(float(open(sleep).read()))
code = os.path.join(d, "code")
sys.exit(int(open(code).read()) if os.path.exists(code) else 0)
'''

USAGE = {"ok": False, "error": {"type": "Usage", "message": "usage: notify.py TITLE BODY"}}
SENT = {"ok": True, "sent": True}
NOT_SENT = {"ok": True, "sent": False}


def write_exec(path, text):
    path.write_text(text)
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


@pytest.fixture
def world(tmp_path):
    """An empty temp bin dir (the whole PATH) and the stub's fixture dir."""
    bindir = tmp_path / "bin"
    bindir.mkdir()
    notify = tmp_path / "notify"
    notify.mkdir()
    return {"bin": bindir, "notify": notify}


def install_stub(world, text=None):
    """Put an executable notify-send in bin/: the logging stub, or `text`."""
    write_exec(world["bin"] / "notify-send",
               STUB.replace("@PYTHON@", sys.executable) if text is None else text)


def env_for(world, **extra):
    e = {"PATH": str(world["bin"]), "FAKE_NOTIFY_DIR": str(world["notify"])}
    e.update(extra)
    return e


def run(world, args, **extra):
    """Run the helper; assert stdout is exactly one JSON line; return (exit, payload)."""
    p = subprocess.run([sys.executable, SCRIPT, *args], capture_output=True, text=True,
                       env=env_for(world, **extra), timeout=60)
    lines = p.stdout.splitlines()
    assert len(lines) == 1, (p.stdout, p.stderr)
    return p.returncode, json.loads(lines[0])


def calls(world):
    log = world["notify"] / "calls.log"
    return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []


def set_fixture(world, name, data):
    """FAKE_NOTIFY_DIR/<name> holds `data` (str or bytes)."""
    (world["notify"] / name).write_bytes(data if isinstance(data, bytes) else data.encode())


# --- notify-send missing ------------------------------------------------------

def test_without_notify_send_nothing_is_sent(world):
    assert run(world, ["Run r1", "needs a human"]) == (0, NOT_SENT)


def test_non_executable_notify_send_counts_as_missing(world):
    path = world["bin"] / "notify-send"
    path.write_text("#!/bin/sh\necho hi\n")
    path.chmod(0o644)
    assert run(world, ["Run r1", "needs a human"]) == (0, NOT_SENT)
    assert path.read_text() == "#!/bin/sh\necho hi\n"
    assert calls(world) == []


# --- sent -----------------------------------------------------------------------

def test_sent_with_title_and_body_after_dashdash(world):
    install_stub(world)
    assert run(world, ["Run r1", "needs a human"]) == (0, SENT)
    assert calls(world) == [["--", "Run r1", "needs a human"]]


def test_notify_send_stdout_never_reaches_ours(world):
    install_stub(world)
    p = subprocess.run([sys.executable, SCRIPT, "Run r1", "b"], capture_output=True, text=True,
                       env=env_for(world), timeout=60)
    assert "stdout noise" not in p.stdout
    assert json.loads(p.stdout) == SENT


def test_args_reach_notify_send_verbatim(world):
    install_stub(world)
    title = "-u critical"
    body = "line one\nline two $HOME; echo 'hi' \"there\" \u00e9 \u203c"
    assert run(world, [title, body]) == (0, SENT)
    assert calls(world) == [["--", title, body]]


def test_empty_body_is_sent(world):
    install_stub(world)
    assert run(world, ["Run r1", ""]) == (0, SENT)
    assert calls(world) == [["--", "Run r1", ""]]


def test_title_whitespace_is_sent_verbatim(world):
    install_stub(world)
    assert run(world, ["  Run r1  ", "b"]) == (0, SENT)
    assert calls(world) == [["--", "  Run r1  ", "b"]]


def test_dashdash_title_and_dash_body_reach_notify_send(world):
    install_stub(world)
    assert run(world, ["--", "-b"]) == (0, SENT)
    assert calls(world) == [["--", "--", "-b"]]


# --- usage ----------------------------------------------------------------------

@pytest.mark.parametrize("args", [[], ["Run r1"], ["Run r1", "b", "extra"],
                                  ["  ", "b"], ["", "b"], ["\t\n", "b"]])
def test_usage(world, args):
    install_stub(world)
    assert run(world, args) == (2, USAGE)
    assert not (world["notify"] / "calls.log").exists()


def test_usage_wins_over_missing_notify_send(world):
    assert run(world, []) == (2, USAGE)
