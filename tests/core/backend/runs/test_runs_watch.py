"""runs-watch.py: `am watch --all-projects --follow` turned into nudges and a cursor.

Hermetic: a fake `am` on a temp PATH replays FAKE_AM_DIR/script.json: a list of
steps (a JSON line, raw text, or a sleep), then a chosen stderr text and exit
code. The JSON lines are copies of the committed captures in tests/fixtures/am/;
a line no capture holds is labelled `synthetic:`. The fake am logs its argv to
calls.log and its pid to pid. HOME and XDG_* are temp. The real `am` and real
data are never touched.
"""
import json
import os
import signal
import stat
import subprocess
import sys
import time

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..", "..", "..")
SCRIPT = os.path.join(ROOT, "core", "backend", "runs", "runs-watch.py")
USAGE = "usage: runs-watch.py <root> [<root> ...] [run_id ...] [--since-seq N]"

FAKE_AM = r'''#!/usr/bin/env python3
import json, os, sys, time
d = os.environ["FAKE_AM_DIR"]
with open(os.path.join(d, "calls.log"), "a") as f:
    f.write(json.dumps(sys.argv[1:]) + "\n")
with open(os.path.join(d, "pid"), "w") as f:
    f.write(str(os.getpid()))
with open(os.path.join(d, "script.json")) as f:
    script = json.load(f)
for step in script["steps"]:
    if "sleep" in step:
        time.sleep(step["sleep"])
        continue
    if "raw" in step:
        sys.stdout.write(step["raw"] + "\n")
    else:
        sys.stdout.write(json.dumps(step["line"], separators=(",", ":")) + "\n")
    sys.stdout.flush()
sys.stderr.write(script.get("stderr", ""))
sys.stderr.flush()
sys.exit(script.get("exit", 0))
'''

MISSING = object()
FIXTURES = os.path.join(ROOT, "tests", "fixtures", "am")


def fixture(name):
    """A fresh json.load of tests/fixtures/am/<name>, so an edit never reaches
    another call."""
    with open(os.path.join(FIXTURES, name)) as f:
        return json.load(f)


def events():
    """A fresh copy of the captured journal lines, in gseq order."""
    return fixture("watch-events.json")["data"]["events"]


# The run of every captured journal line.
RUN = events()[0]["run_id"]
# The project root of the captured run: its run_upsert's payload.repo_dir.
CAPTURE_ROOT = events()[1]["payload"]["repo_dir"]
# The default argv: the capture's root, the captured run and the synthetic r2.
ARGS = [CAPTURE_ROOT, RUN, "r2"]
# A root for argv tests; it never has to exist.
SOME_ROOT = "/some/root"
# The event kinds am 0.2.0 writes; the helper nudges on exactly these.
KINDS = ["run_upsert", "story_upsert", "subtask_upsert", "phase_upsert", "attempt_upsert",
         "lease_acquired", "lease_taken_over", "control_requested", "control_handled",
         "claim_conflict"]


def hello_out(line):
    """The helper's hello output line for a captured hello line that has head."""
    return {"hello": {"schema": line["schema"], "am": line["am"], "head": line["head"],
                      "cursorReset": line["cursor_reset"], "storeId": line["store_id"]}}


HELLO = hello_out(fixture("watch-hello.json")["schema_2"])


def write_exec(path, text):
    path.write_text(text)
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


@pytest.fixture
def world(tmp_path):
    """A temp PATH with a fake am, its script dir and a temp HOME."""
    bindir = tmp_path / "bin"
    bindir.mkdir()
    write_exec(bindir / "am", FAKE_AM)
    amdir = tmp_path / "am"
    amdir.mkdir()
    home = tmp_path / "home"
    home.mkdir()
    return {"tmp": tmp_path, "bin": bindir, "am": amdir, "home": home}


def env_for(world, **extra):
    e = {
        "PATH": str(world["bin"]) + os.pathsep + "/usr/bin" + os.pathsep + "/bin",
        "HOME": str(world["home"]),
        "FAKE_AM_DIR": str(world["am"]),
    }
    for name in ("XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
        e[name] = str(world["tmp"] / name.lower())
    e.update(extra)
    return e


def hello(schema=2, **edits):
    """The --follow hello: the captured schema_2 line (am 0.2.0), or the captured
    schema_1 line (an old am, no head) for schema=1. synthetic: any other schema
    value is set on a schema_2 copy, MISSING drops the key. synthetic: each of
    edits (am, head, cursor_reset, store_id or any other key) is set on the
    copy, MISSING drops the key."""
    lines = fixture("watch-hello.json")
    if type(schema) is int and schema in (1, 2):
        line = lines["schema_%d" % schema]
    else:
        line = lines["schema_2"]
        edits = {"schema": schema, **edits}
    for key, value in edits.items():
        if value is MISSING:
            line.pop(key, None)
        else:
            line[key] = value
    return {"line": line}


def ev(event="phase_upsert"):
    """The first captured journal line whose event is `event`."""
    return {"line": next(e for e in events() if e["event"] == event)}


def nth(i):
    """Captured journal line i (gseq 358 + i)."""
    return {"line": events()[i]}


def gseq(step):
    return step["line"]["gseq"]


def other(run_id, gseq, event="phase_upsert", payload_keys=None, **extra):
    """synthetic: a line the single-run capture has no copy of, built on a copy of
    ev(event) (an event no capture has is laid on a phase_upsert copy): run_id,
    gseq and event set to the given values, MISSING drops the key; payload_keys
    and extra add keys to the payload and the top level."""
    kinds = [e["event"] for e in events()]
    line = ev(event if event in kinds else "phase_upsert")["line"]
    for key, value in (("run_id", run_id), ("gseq", gseq), ("event", event)):
        if value is MISSING:
            del line[key]
        else:
            line[key] = value
    line["payload"].update(payload_keys or {})
    line.update(extra)
    return {"line": line}


def pause(seconds):
    return {"sleep": seconds}


def raw(text):
    return {"raw": text}


def set_script(world, steps, exit=0, stderr=""):
    (world["am"] / "script.json").write_text(
        json.dumps({"steps": steps, "exit": exit, "stderr": stderr}))


def run_helper(world, args=ARGS, timeout=30, cwd=None, **extra):
    """Run the helper until it exits (default argv: ARGS) in `cwd` (default: this
    process's). Every stdout line must be JSON. Returns (exit code, parsed lines,
    stderr)."""
    p = subprocess.run([sys.executable, SCRIPT, *args], capture_output=True, text=True,
                       env=env_for(world, **extra), timeout=timeout, cwd=cwd)
    return p.returncode, [json.loads(line) for line in p.stdout.splitlines()], p.stderr


def changed(lines):
    """`lines` as changed/cursor pairs: [(sorted [(run, seq)], cursor), ...]
    (entry order inside a changed line is not part of the contract). Each changed
    line is exactly {"changed": [...]}, non-empty, its entries exactly
    {"run": str, "seq": int} with no run twice, and is followed directly by
    exactly {"cursor": int}."""
    assert len(lines) % 2 == 0, lines
    pairs = []
    for line, cursor in zip(lines[::2], lines[1::2]):
        assert set(line) == {"changed"}, line
        entries = line["changed"]
        assert isinstance(entries, list) and entries, line
        for entry in entries:
            assert set(entry) == {"run", "seq"}, line
            assert isinstance(entry["run"], str) and type(entry["seq"]) is int, line
        runs = [entry["run"] for entry in entries]
        assert len(runs) == len(set(runs)), line
        assert set(cursor) == {"cursor"} and type(cursor["cursor"]) is int, cursor
        pairs.append((sorted((e["run"], e["seq"]) for e in entries), cursor["cursor"]))
    return pairs


def split(lines, greeting=HELLO):
    """The lines after the leading hello line, which must be `greeting`."""
    assert lines, lines
    assert lines[0] == greeting, lines
    return lines[1:]


def calls(world):
    log = world["am"] / "calls.log"
    return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []


# --- the lines are capture copies -----------------------------------------------

def test_lines_are_capture_copies():
    captured = events()
    for name in ["lease_acquired", "run_upsert", "story_upsert", "subtask_upsert",
                 "phase_upsert", "attempt_upsert"]:
        assert ev(name)["line"] == next(e for e in captured if e["event"] == name)
    for i in (0, 18, 59):
        assert nth(i)["line"] == captured[i]
    assert hello(1) == {"line": fixture("watch-hello.json")["schema_1"]}
    assert "head" not in hello(1)["line"]
    assert hello() == hello(2) == {"line": fixture("watch-hello.json")["schema_2"]}
    assert HELLO == {"hello": {"schema": 2, "am": "0.1.0", "head": 1005, "cursorReset": False,
                               "storeId": "91b9e8afc25044c385859292bfabfde7"}}
    # What the tests below rely on: one run, gseq strictly increasing from 358,
    # and a per-run seq that never equals the gseq.
    assert {e["run_id"] for e in captured} == {RUN}
    assert [e["gseq"] for e in captured] == list(range(358, 358 + len(captured)))
    assert all(e["seq"] != e["gseq"] for e in captured)
    assert gseq(ev()) == 376
    # The capture's only run_upsert is nth(1); nth(0) (lease_acquired) comes before it.
    assert [i for i, e in enumerate(captured) if e["event"] == "run_upsert"] == [1]
    assert captured[0]["event"] == "lease_acquired"
    assert CAPTURE_ROOT == nth(1)["line"]["payload"]["repo_dir"]
    assert CAPTURE_ROOT == "/home/user/Code/omarchy-project-manager"


# --- argv, am missing, clean exit -----------------------------------------------

def test_argv_default(world):
    set_script(world, [hello()])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == [HELLO]
    # argv list, no shell: the fake am sees exactly these arguments.
    assert calls(world) == [["watch", "--all-projects", "--follow"]]


@pytest.mark.parametrize("value, passed", [("0", "0"), ("1005", "1005"), ("007", "7")])
def test_argv_since_seq(world, value, passed):
    set_script(world, [hello()])
    code, lines, _ = run_helper(world, [CAPTURE_ROOT, "--since-seq", value])
    assert code == 0
    assert lines == [HELLO]
    assert calls(world) == [["watch", "--all-projects", "--follow", "--since-seq", passed]]


@pytest.mark.parametrize("args, passed", [
    (["/repoA", RUN, "/repoB", "--since-seq", "7", "x1"], ["--since-seq", "7"]),
    (["x1", "/repoA"], []),
], ids=["mixed-with-since-seq", "run-id-first"])
def test_argv_roots_and_run_ids_never_reach_am(world, args, passed):
    set_script(world, [hello()])
    code, lines, _ = run_helper(world, args)
    assert code == 0
    assert lines == [HELLO]
    assert calls(world) == [["watch", "--all-projects", "--follow", *passed]]


@pytest.mark.parametrize("args", [
    [RUN], ["--since-seq"], ["--since-seq", "-1"],
    ["--since-seq", "abc"], ["--since-seq", "5.0"], ["--since-seq", ""],
    ["--since-seq", "1", "--since-seq", "2"], ["--since-seq=5"], ["--from-now"],
    ["--since-seq", "5", "extra"], ["--since-seq", "٣"], ["--since-seq", "+5"],
    ["--since-seq", " 5"],
    [SOME_ROOT, "--since-seq"], [SOME_ROOT, "--since-seq", "-1"],
    [SOME_ROOT, "--since-seq", "abc"], [SOME_ROOT, "--since-seq", "1", "--since-seq", "2"],
    [SOME_ROOT, "--since-seq=5"], [SOME_ROOT, "--from-now"], [SOME_ROOT, "-x"],
    [SOME_ROOT, ""], [RUN, "--since-seq", "5"], [],
], ids=["run", "no-value", "negative", "letters", "float", "empty",
        "twice", "equals-form", "other-flag", "trailing-arg", "arabic-indic-digit", "plus-sign",
        "leading-space",
        "root-no-value", "root-negative", "root-letters", "root-twice", "root-equals-form",
        "root-other-flag", "root-dash-x", "root-empty", "run-since-seq-no-root", "no-argument"])
def test_usage(world, args):
    set_script(world, [hello()])
    code, lines, _ = run_helper(world, args)
    assert code == 2
    assert lines == [{"ok": False, "error": {"type": "Usage", "message": USAGE}}]
    assert calls(world) == []  # am never spawned


def test_usage_before_am_lookup(world):
    empty = world["tmp"] / "empty-bin"
    empty.mkdir()
    code, lines, _ = run_helper(world, [RUN], PATH=str(empty))  # no root
    assert code == 2
    assert lines == [{"ok": False, "error": {"type": "Usage", "message": USAGE}}]


def test_am_missing(world):
    empty = world["tmp"] / "empty-bin"
    empty.mkdir()
    code, lines, _ = run_helper(world, PATH=str(empty))
    assert code == 1
    assert len(lines) == 1, lines
    assert lines[0]["ok"] is False
    assert lines[0]["error"]["type"] == "AmMissing"
    assert lines[0]["error"]["message"] == "am is not installed."


def test_clean_exit_zero(world):
    set_script(world, [hello()])
    code, lines, err = run_helper(world)
    assert code == 0
    assert lines == [HELLO]
    assert "Traceback" not in err


# --- the hello line ---------------------------------------------------------------

def test_hello_forwarded(world):
    # Exactly five keys: runs_dir and event are not forwarded.
    set_script(world, [hello(2), ev()])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines[0] == HELLO
    assert set(lines[0]["hello"]) == {"schema", "am", "head", "cursorReset", "storeId"}


def assert_schema_mismatch(world, lines, began, needle):
    assert time.monotonic() - began < 5
    assert lines[-1]["ok"] is False, lines
    assert lines[-1]["error"]["type"] == "SchemaMismatch", lines
    assert needle in lines[-1]["error"]["message"], lines
    assert_gone(am_pid(world))  # am was terminated, not left streaming


def test_hello_without_head_is_schema_mismatch(world):
    # The schema_1 capture is an old am's hello: no head. am would keep
    # streaming for 8 s; the helper must stop it and leave at once.
    set_script(world, [hello(1), ev(), pause(8)])
    began = time.monotonic()
    code, lines, _ = run_helper(world)
    assert code == 1
    assert len(lines) == 1, lines
    assert_schema_mismatch(world, lines, began, "the plugin needs the newer am")


@pytest.mark.parametrize("head", [MISSING, None, "1005", -1, True, 1005.0],
                         ids=["synthetic: missing", "synthetic: null", "synthetic: string",
                              "synthetic: negative", "synthetic: true", "synthetic: float"])
def test_hello_bad_head(world, head):
    set_script(world, [hello(2, head=head), ev(), pause(8)])
    began = time.monotonic()
    code, lines, _ = run_helper(world)
    assert code == 1
    assert len(lines) == 1, lines
    assert_schema_mismatch(world, lines, began, "the plugin needs the newer am")


@pytest.mark.parametrize("schema", [0, -1, "2", True, 2.0, None, MISSING],
                         ids=["synthetic: zero", "synthetic: negative", "synthetic: string-two",
                              "synthetic: true", "synthetic: two-float", "synthetic: null",
                              "synthetic: missing"])
def test_schema_mismatch(world, schema):
    set_script(world, [hello(schema), ev(), pause(8)])
    began = time.monotonic()
    code, lines, _ = run_helper(world)
    assert code == 1
    assert len(lines) == 1, lines
    received = json.dumps(None if schema is MISSING else schema)
    assert_schema_mismatch(world, lines, began, "schema " + received)
    assert "1 or higher" in lines[0]["error"]["message"], lines


def test_schema_above_two_accepted(world):
    set_script(world, [hello(3), ev()])  # synthetic: schema 3 with head
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines[0] == {"hello": {**HELLO["hello"], "schema": 3}}


@pytest.mark.parametrize("edits, expect", [
    ({"am": MISSING}, {"am": ""}),
    ({"am": 5}, {"am": ""}),
    ({"am": None}, {"am": ""}),
    ({"cursor_reset": True}, {"cursorReset": True}),
    ({"cursor_reset": MISSING}, {"cursorReset": False}),
    ({"cursor_reset": 1}, {"cursorReset": False}),
    ({"cursor_reset": "true"}, {"cursorReset": False}),
    ({"cursor_reset": None}, {"cursorReset": False}),
    ({"store_id": MISSING}, {"storeId": ""}),
    ({"store_id": 5}, {"storeId": ""}),
    ({"shiny": {"new": 1}}, {}),
], ids=["synthetic: am missing", "synthetic: am number", "synthetic: am null",
        "synthetic: cursor_reset true", "synthetic: cursor_reset missing",
        "synthetic: cursor_reset one", "synthetic: cursor_reset string",
        "synthetic: cursor_reset null", "synthetic: store_id missing",
        "synthetic: store_id number", "synthetic: unknown key"])
def test_hello_field_coercion(world, edits, expect):
    set_script(world, [hello(2, **edits), ev()])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines[0] == {"hello": {**HELLO["hello"], **expect}}


def test_hello_forwarded_once(world):
    # synthetic: a second hello with another head, a third with schema 3.
    set_script(world, [hello(), hello(2, head=2000), hello(3), ev()])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert [line for line in lines if "hello" in line] == [HELLO]


@pytest.mark.parametrize("steps, needle", [
    ([hello(), hello(1), ev(), pause(8)], "the plugin needs the newer am"),
    # the pending batch is not printed
    ([hello(), ev(), hello(0), ev(), pause(8)], "schema 0"),
    ([hello(), ev(), hello(1), pause(8)], "the plugin needs the newer am"),
], ids=["old-am", "synthetic: zero, pending-batch", "old-am, pending-batch"])
def test_later_bad_hello_is_schema_mismatch(world, steps, needle):
    set_script(world, steps)
    began = time.monotonic()
    code, lines, _ = run_helper(world)
    assert code == 1
    assert len(lines) == 2, lines
    assert lines[0] == HELLO
    assert_schema_mismatch(world, lines, began, needle)


def test_hello_mid_batch_keeps_the_batch(world):
    # RUN's line opens a batch; the hello is printed at once without flushing
    # or clearing it, so r2 joins the same changed line.
    r2 = other("r2", 9000)
    set_script(world, [ev(), hello(), r2, pause(0.6)])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert changed(split(lines)) == [(sorted([(RUN, gseq(ev())), ("r2", 9000)]), 9000)]


def test_no_hello_still_streams(world):
    set_script(world, [ev()])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert changed(lines) == [([(RUN, gseq(ev()))], gseq(ev()))]


# --- nudges, batching and the cursor -------------------------------------------

def test_changed_one_run_highest_gseq(world):
    steps = [nth(i) for i in range(10, 20)]
    top = gseq(steps[-1])
    set_script(world, [hello(), *steps, pause(0.6)])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert changed(split(lines)) == [([(RUN, top)], top)]
    assert steps[-1]["line"]["seq"] != top  # the per-run seq is not what is printed


def test_changed_batches_runs_highest_each(world):
    set_script(world, [hello(), nth(0), other("r2", 5000), nth(1), other("r2", 5001), nth(2),
                       pause(0.6)])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert changed(split(lines)) == [(sorted([(RUN, gseq(nth(2))), ("r2", 5001)]), 5001)]


def test_changed_lower_gseq_never_lowers(world):
    # synthetic: r2's gseqs arrive out of order; the second window holds a
    # lower gseq than the cursor.
    set_script(world, [hello(), nth(5), nth(2), other("r2", 900), other("r2", 400), pause(0.6),
                       nth(1), pause(0.6)])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert changed(split(lines)) == [
        (sorted([(RUN, gseq(nth(5))), ("r2", 900)]), 900),
        ([(RUN, gseq(nth(1)))], 900),
    ]


def test_changed_never_carries_event_contents(world):
    secret = "synthetic: do-not-forward"
    set_script(world, [hello(), nth(0), nth(1), nth(18),
                       other("r2", 5000, payload_keys={"secret": secret}), pause(0.6)])
    code, lines, _ = run_helper(world)
    assert code == 0
    for line in lines:
        assert set(line) in ({"hello"}, {"changed"}, {"cursor"}), line
    for entry in [e for line in lines if "changed" in line for e in line["changed"]]:
        assert set(entry) == {"run", "seq"}, entry
    text = json.dumps(lines)
    for value in (secret, nth(1)["line"]["payload"]["repo_dir"], nth(18)["line"]["card"],
                  nth(18)["line"]["story"], nth(18)["line"]["ts"], "phase_upsert",
                  "lease_acquired", "run_upsert"):
        assert value not in text, value


def test_cursor_with_each_changed_line(world):
    set_script(world, [hello(), nth(0), pause(0.6), nth(1), nth(2), pause(0.6)])
    code, lines, _ = run_helper(world)
    assert code == 0
    pairs = changed(split(lines))
    assert pairs == [([(RUN, gseq(nth(0)))], gseq(nth(0))),
                     ([(RUN, gseq(nth(2)))], gseq(nth(2)))]
    assert pairs[1][1] >= pairs[0][1]


def test_debounce_separate_windows(world):
    set_script(world, [hello(), ev(), pause(0.6), ev(), pause(0.6)])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert changed(split(lines)) == [([(RUN, gseq(ev()))], gseq(ev()))] * 2


def test_debounce_continuous_stream_is_rate_limited(world):
    # A line every 50 ms for over a second: the window must still close on time
    # (more than one changed line), and changed lines never come faster than one
    # per 250 ms.
    steps = [hello()]
    for i in range(20):
        steps += [nth(i), pause(0.05)]
    set_script(world, steps)
    began = time.monotonic()
    code, lines, _ = run_helper(world)
    elapsed = time.monotonic() - began
    assert code == 0
    pairs = changed(split(lines))
    assert len(pairs) >= 2, pairs
    assert len(pairs) <= int(elapsed / 0.25) + 1, (len(pairs), elapsed)
    seqs = []
    for entries, cursor in pairs:
        [(run, seq)] = entries
        assert run == RUN
        assert cursor == seq  # one run, increasing gseqs: each window's highest is the cursor
        seqs.append(seq)
    assert seqs == sorted(set(seqs)), seqs
    assert seqs[-1] == gseq(nth(19))


@pytest.mark.parametrize("kind", KINDS, ids=[
    k if k in {e["event"] for e in events()} else "synthetic: " + k for k in KINDS])
def test_every_known_event_nudges(world, kind):
    captured = [e["event"] for e in events()]
    # synthetic: the capture has no line of this kind; it is set on a copy.
    step = ev(kind) if kind in captured else other(RUN, 9000, kind)
    set_script(world, [hello(), step])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert changed(split(lines)) == [([(RUN, gseq(step))], gseq(step))]


# synthetic: lines that are not nudges. Each carries a gseq above every nudge in
# the tests that use it, so a leak would raise the cursor.
IGNORED = [
    other(RUN, 9001, "future_event"),
    other(RUN, 9002, "watch_extra"),
    other(RUN, 9003, 5),
    other(RUN, 9004, ["phase_upsert"]),
    other(RUN, 9005, {"kind": "phase_upsert"}),
    other(RUN, 9006, MISSING),
    other(MISSING, 9007),
    other("", 9008),
    other(5, 9009),
    other(["r"], 9010),
    other(RUN, MISSING),
    other(RUN, 0),
    other(RUN, -1),
    other(RUN, True),
    other(RUN, "9011"),
    other(RUN, 9012.0),
    raw("not json"),
    raw("[1, 2]"),
    raw('"a string"'),
    raw(""),
    raw("9013"),
    raw("null"),
]


def test_ignores_unknown_events_and_keys(world):
    # synthetic: a valid line with unknown top-level and payload keys still nudges.
    kept = other(RUN, 100, payload_keys={"shiny": {"new": 1}}, brand_new_key=[1, 2, 3])
    set_script(world, [hello(), *IGNORED, kept, pause(0.6)])
    code, lines, err = run_helper(world)
    assert code == 0
    assert "Traceback" not in err
    assert changed(split(lines)) == [([(RUN, 100)], 100)]


def test_only_ignored_lines_print_nothing(world):
    set_script(world, [hello(), *IGNORED, pause(0.6)])
    code, lines, err = run_helper(world)
    assert code == 0
    assert "Traceback" not in err
    assert lines == [HELLO]


def test_pending_batch_flushed_at_eof(world):
    # am exits 0 inside the window.
    set_script(world, [hello(), nth(0), nth(3)])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == [HELLO, {"changed": [{"run": RUN, "seq": gseq(nth(3))}]},
                     {"cursor": gseq(nth(3))}]


# --- how am ended ----------------------------------------------------------------

def test_exit_3_corrupt_journal(world):
    # synthetic: am's stderr text for a corrupt journal.
    set_script(world, [hello(), ev()], exit=3,
               stderr="am watch: journal line 4 of run r1 is not JSON\n")
    code, lines, _ = run_helper(world)
    assert code == 1
    assert len(lines) == 4, lines
    assert lines[0] == HELLO
    # the pending batch is flushed first
    assert changed(lines[1:3]) == [([(RUN, gseq(ev()))], gseq(ev()))]
    assert lines[3]["ok"] is False
    assert lines[3]["error"]["type"] == "CorruptJournal"
    assert "journal line 4 of run r1 is not JSON" in lines[3]["error"]["message"]


def test_other_exit_is_helper_error(world):
    # synthetic: am's stderr text for a crash.
    set_script(world, [hello(), ev()], exit=1, stderr="boom\n")
    code, lines, _ = run_helper(world)
    assert code == 1
    assert len(lines) == 4, lines
    assert lines[0] == HELLO
    assert changed(lines[1:3]) == [([(RUN, gseq(ev()))], gseq(ev()))]
    assert lines[3]["ok"] is False
    assert lines[3]["error"]["type"] == "HelperError"
    assert "boom" in lines[3]["error"]["message"]


def test_refusal_exit_3_is_corrupt_journal(world):
    # synthetic: an am refusal envelope; no capture holds one.
    envelope = {"error": {"message": "run r1: journal line 2 is not JSON",
                          "type": "CorruptJournalError"}, "ok": False}
    set_script(world, [{"line": envelope}], exit=3)
    code, lines, _ = run_helper(world)
    assert code == 1
    assert len(lines) == 1, lines
    assert lines[0]["ok"] is False
    assert lines[0]["error"]["type"] == "CorruptJournal"
    assert lines[0]["error"]["message"] == "run r1: journal line 2 is not JSON"


def test_refusal_other_exit_is_reemitted(world):
    # synthetic: an am refusal envelope; no capture holds one.
    envelope = {"error": {"message": "something else", "type": "OddError"}, "ok": False}
    set_script(world, [{"line": envelope}], exit=0)
    code, lines, _ = run_helper(world)
    assert code == 1
    assert lines == [envelope]


def test_refusal_after_hello_is_reemitted(world):
    # synthetic: an am refusal envelope; no capture holds one.
    envelope = {"error": {"message": "something else", "type": "OddError"}, "ok": False}
    set_script(world, [hello(), {"line": envelope}], exit=0)
    code, lines, _ = run_helper(world)
    assert code == 1
    assert lines == [HELLO, envelope]


# synthetic: am's StoreBusyError envelope (the shape of am's error_envelope);
# no capture holds one.
STORE_BUSY = {"error": {"message": "the am store is busy; try again",
                        "type": "StoreBusyError"}, "ok": False}


def test_refusal_store_busy_is_reemitted(world):
    set_script(world, [{"line": STORE_BUSY}], exit=3)
    code, lines, _ = run_helper(world)
    assert code == 1
    assert lines == [STORE_BUSY]


def test_refusal_store_busy_after_batch_is_reemitted(world):
    set_script(world, [hello(), ev(), {"line": STORE_BUSY}], exit=3)
    code, lines, _ = run_helper(world)
    assert code == 1
    assert len(lines) == 4, lines
    assert lines[0] == HELLO
    assert changed(lines[1:3]) == [([(RUN, gseq(ev()))], gseq(ev()))]  # flushed first
    assert lines[3] == STORE_BUSY


# --- stopping: signals and a closed stdout ---------------------------------------

def start_helper(world, args=ARGS):
    return subprocess.Popen([sys.executable, SCRIPT, *args], stdin=subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                            env=env_for(world))


def am_pid(world):
    return int((world["am"] / "pid").read_text())


def assert_gone(pid, within=5.0):
    """The fake am process no longer exists (no orphaned `am watch`)."""
    end = time.monotonic() + within
    while time.monotonic() < end:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return
        time.sleep(0.05)
    os.kill(pid, signal.SIGKILL)
    pytest.fail("am watch was left running after the helper exited")


@pytest.mark.parametrize("sig", [signal.SIGTERM, signal.SIGINT], ids=["SIGTERM", "SIGINT"])
def test_signal_stops_am_and_exits_zero(world, sig):
    set_script(world, [hello(), ev(), pause(30)])
    p = start_helper(world)
    try:
        assert json.loads(p.stdout.readline()) == HELLO
        # sync point: am is running, helper is streaming
        assert json.loads(p.stdout.readline()) == {"changed": [{"run": RUN, "seq": gseq(ev())}]}
        assert json.loads(p.stdout.readline()) == {"cursor": gseq(ev())}
        p.send_signal(sig)
        code = p.wait(timeout=10)
    finally:
        if p.poll() is None:
            p.kill()
            p.wait()
    err = p.stderr.read()
    p.stdout.close()
    p.stderr.close()
    assert code == 0, err
    assert "Traceback" not in err
    assert_gone(am_pid(world))


def test_closed_stdout_exits_zero(world):
    set_script(world, [hello(), ev(), pause(0.6), ev(), pause(30)])
    p = start_helper(world)
    p.stdout.close()  # the reader goes away before the first changed line
    try:
        code = p.wait(timeout=10)
    finally:
        if p.poll() is None:
            p.kill()
            p.wait()
    err = p.stderr.read()
    p.stderr.close()
    assert code == 0, err
    assert "Traceback" not in err
    assert "BrokenPipeError" not in err
    assert_gone(am_pid(world))
