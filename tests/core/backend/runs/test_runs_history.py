"""runs-history.py: one page of a project's older runs, one JSON line on every path.

Hermetic: a fake `am` lives on a temp PATH and serves, from FAKE_AM_DIR, rows and
status replies built from the committed captures in tests/fixtures/am/ (every
edited payload is labelled `synthetic:`), appending each call's argv to
calls.log; HOME and XDG_DATA_HOME are temp. The real `am` and real data are
never touched.
"""
import datetime
import json
import os
import stat
import subprocess
import sys

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..", "..", "..")
SCRIPT = os.path.join(ROOT, "core", "backend", "runs", "runs-history.py")

# The fake am logs its argv, then prints FAKE_AM_DIR/<name>.out verbatim and exits
# with FAKE_AM_DIR/<name>.code (default 0), where <name> is "runs" or
# "status-<run id>". A status fixture that does not exist behaves like real am for
# an unknown run: an UnknownRunError envelope and exit 3.
FAKE_AM = '''#!/usr/bin/env python3
import json, os, sys
d = os.environ["FAKE_AM_DIR"]
args = sys.argv[1:]
with open(os.path.join(d, "calls.log"), "a") as f:
    f.write(json.dumps(args) + "\\n")
name = "runs" if args[:1] == ["runs"] else "status-" + (args[1] if len(args) > 1 else "")
out = os.path.join(d, name + ".out")
if not os.path.exists(out):
    sys.stdout.write(json.dumps({"error": {"message": "unknown run", "type": "UnknownRunError"}, "ok": False}) + "\\n")
    sys.exit(3)
with open(out) as f:
    sys.stdout.write(f.read())
code = os.path.join(d, name + ".code")
sys.exit(int(open(code).read()) if os.path.exists(code) else 0)
'''

FIXTURES = os.path.join(ROOT, "tests", "fixtures", "am")
# synthetic: am error envelopes; no capture holds one.
UNKNOWN_RUN = {"error": {"message": "unknown run", "type": "UnknownRunError"}, "ok": False}
REPO_DIR_ERROR = {"error": {"message": "not a git repository", "type": "RepoDirError"}, "ok": False}
USAGE = "usage: runs-history.py ROOT --before ISO [--limit K] [--status S,...] [--since ISO]"
BEFORE = "2026-10-09T00:00:00Z"
TERMINAL = ["done", "escalated", "stopped", "cancelled", "canceled"]
NOON = datetime.datetime(2026, 10, 8, 12, tzinfo=datetime.timezone.utc)


def LIST(root):
    """The one `am runs` argv: the project filter alone, no --limit or --before."""
    return ["runs", "--repo-dir", root]


def STATUS(run_id):
    """The `am status` argv for one run: never a --repo-dir."""
    return ["status", run_id]


def fixture(name):
    """A fresh json.load of tests/fixtures/am/<name>, so an edit never reaches
    another call."""
    with open(os.path.join(FIXTURES, name)) as f:
        return json.load(f)


def write_exec(path, text):
    path.write_text(text)
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


@pytest.fixture
def world(tmp_path):
    """A temp PATH with a fake am, its fixture dir, a temp HOME/XDG_DATA_HOME, and a
    project root whose name would break if it ever went through a shell."""
    bindir = tmp_path / "bin"
    bindir.mkdir()
    write_exec(bindir / "am", FAKE_AM)
    amdir = tmp_path / "am"
    amdir.mkdir()
    home = tmp_path / "home"
    home.mkdir()
    proj = tmp_path / "my proj; echo x"
    proj.mkdir()
    return {"tmp": tmp_path, "bin": bindir, "am": amdir, "home": home,
            "data": tmp_path / "data", "proj": proj}


def env_for(world, drop=(), **extra):
    e = {
        "PATH": str(world["bin"]) + os.pathsep + "/usr/bin" + os.pathsep + "/bin",
        "HOME": str(world["home"]),
        "XDG_DATA_HOME": str(world["data"]),
        "FAKE_AM_DIR": str(world["am"]),
    }
    e.update(extra)
    for key in drop:
        e.pop(key, None)
    return e


def run(world, args, drop=(), **extra):
    """Run the helper with `args`; assert stdout is exactly one JSON line; return
    (exit, payload)."""
    p = subprocess.run([sys.executable, SCRIPT, *args], capture_output=True, text=True,
                       env=env_for(world, drop, **extra), timeout=60)
    lines = p.stdout.splitlines()
    assert len(lines) == 1, (p.stdout, p.stderr)
    return p.returncode, json.loads(lines[0])


def row(run_id, status, started_at):
    """synthetic: a test-local id, status and started_at set on a copy of the
    captured done row of `am runs`."""
    r = fixture("runs.json")["data"]["runs"][1]
    r["id"] = run_id
    r["status"] = status
    r["started_at"] = started_at
    return r


def stamp(i):
    """synthetic: the started_at of the i-th newest row, i minutes before noon UTC
    on 2026-10-08."""
    return (NOON - datetime.timedelta(minutes=i)).isoformat()


def rows(n, status="done"):
    """synthetic: n rows d0..d<n-1> of `status`, newest first."""
    return [row("d%d" % i, status, stamp(i)) for i in range(n)]


def status_data(run_id):
    """synthetic: the captured done `am status` data with run.id set to `run_id`."""
    data = fixture("status-done.json")["data"]
    data["run"]["id"] = run_id
    return data


def set_runs(world, runs):
    """`am runs` serves the captured envelope without `_note`, its runs replaced by
    `runs` (synthetic)."""
    envelope = {k: v for k, v in fixture("runs.json").items() if not k.startswith("_")}
    envelope["data"]["runs"] = runs
    (world["am"] / "runs.out").write_text(json.dumps(envelope) + "\n")


def set_status(world, run_id, data):
    (world["am"] / ("status-" + run_id + ".out")).write_text(
        json.dumps({"data": data, "ok": True}) + "\n")


def seed(world, runs):
    """`am runs` lists `runs`; `am status` answers for every one of them."""
    set_runs(world, runs)
    for r in runs:
        set_status(world, r["id"], status_data(r["id"]))


def set_raw(world, name, text, code=0):
    (world["am"] / (name + ".out")).write_text(text)
    (world["am"] / (name + ".code")).write_text(str(code))


def calls(world):
    log = world["am"] / "calls.log"
    return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []


def ids(out):
    return [r["id"] for r in out["runs"]]


def args_for(world, *extra):
    """The project root, `--before BEFORE`, then `extra`."""
    return [str(world["proj"]), "--before", BEFORE, *extra]


# --- usage, am missing ---------------------------------------------------------

B = BEFORE


@pytest.mark.parametrize("args", [
    [],
    ["/root"],
    ["--before", B],
    ["/root", "--before"],
    ["/root", "--before", ""],
    ["/root", "--before", "-1"],
    ["/root", "--before", "notatime"],
    ["/root", "--before", B, "--since", "notatime"],
    ["/root", "--before", B, "--limit", "0"],
    ["/root", "--before", B, "--limit", "00"],
    ["/root", "--before", B, "--limit", "-1"],
    ["/root", "--before", B, "--limit", "2.5"],
    ["/root", "--before", B, "--limit", "x"],
    ["/root", "--before", B, "--limit", "２"],
    ["/root", "--before", B, "--limit", "٣"],
    ["/root", "--before", B, "--status", ""],
    ["/root", "--before", B, "--status", "a,,b"],
    ["/root", "--before", B, "--status", "done,"],
    ["/root", "--before", B, "--status", ",done"],
    ["/root", "--before=" + B],
    ["/root", "--before", B, "--before", B],
    ["/a", "/b", "--before", B],
    ["", "--before", B],
    ["/root", "--before", B, "--bogus", "x"],
    ["/root", "--before", B, "-h"],
], ids=[
    "none", "root-only", "no-root", "before-no-value", "before-empty", "before-dash",
    "before-bad", "since-bad", "limit-zero", "limit-zeros", "limit-negative",
    "limit-float", "limit-word", "limit-fullwidth", "limit-arabic-indic",
    "status-empty", "status-empty-item", "status-trailing-comma", "status-leading-comma",
    "before-equals", "before-twice", "two-roots", "empty-root", "unknown-flag", "help",
])
def test_usage(world, args):
    code, out = run(world, args)
    assert code == 2
    assert out == {"ok": False, "error": {"type": "Usage", "message": USAGE}}
    assert calls(world) == []


def test_usage_before_am_lookup(world):
    # Bad argv is Usage even when am is not installed: argv is checked first.
    empty = world["tmp"] / "empty-bin"
    empty.mkdir()
    code, out = run(world, ["/root"], PATH=str(empty))
    assert code == 2
    assert out == {"ok": False, "error": {"type": "Usage", "message": USAGE}}


def test_am_missing(world):
    empty = world["tmp"] / "empty-bin"
    empty.mkdir()
    code, out = run(world, args_for(world), PATH=str(empty))
    assert code == 1
    assert out == {"ok": False, "error": {"type": "AmMissing", "message": "am is not installed."}}


# --- the am runs call ------------------------------------------------------------

def test_runs_am_runs_with_repo_dir_only(world):
    # The project dir is named "my proj; echo x": it must arrive as one argv element.
    seed(world, rows(1))
    code, _ = run(world, args_for(world, "--limit", "5", "--since", "2026-10-01T00:00:00Z"))
    assert code == 0
    assert calls(world)[0] == LIST(str(world["proj"]))


def test_option_order_is_free(world):
    seed(world, rows(5))
    root = str(world["proj"])
    first = run(world, ["--before", BEFORE, root, "--limit", "3"])
    first_calls = calls(world)
    (world["am"] / "calls.log").unlink()
    second = run(world, [root, "--limit", "3", "--before", BEFORE])
    assert first == second
    assert first_calls == calls(world)
    code, out = first
    assert code == 0
    assert ids(out) == ["d0", "d1", "d2"]
    assert out["more"] is True


def test_am_runs_envelope_passthrough(world):
    set_raw(world, "runs", json.dumps(REPO_DIR_ERROR) + "\n", code=2)
    code, out = run(world, args_for(world))
    assert code == 1
    assert out == REPO_DIR_ERROR
    assert calls(world) == [LIST(str(world["proj"]))]


@pytest.mark.parametrize("text", [
    "not json\n",
    "[]\n",
    "{}\n",
    json.dumps({"ok": True, "data": {"as_of_seq": 1}}) + "\n",
    json.dumps({"ok": True, "data": None}) + "\n",
    json.dumps({"ok": True, "data": {"runs": [
        {"status": "done", "started_at": "2026-10-08T11:00:00+00:00"}]}}) + "\n",
], ids=["non-json", "list", "no-ok", "no-runs", "data-null", "row-without-id"])
def test_am_runs_bad_output(world, text):
    # synthetic: am runs output no capture holds.
    set_raw(world, "runs", text)
    code, out = run(world, args_for(world))
    assert code == 1
    assert out["ok"] is False
    assert out["error"]["type"] == "AmBadOutput"
    assert calls(world) == [LIST(str(world["proj"]))]


DROP = object()


@pytest.mark.parametrize("started_at", [DROP, None, "yesterday", 5],
                         ids=["missing", "null", "words", "number"])
def test_bad_started_at_is_bad_output(world, started_at):
    # The bad row is `started`, so the status filter would drop it: it still fails.
    bad = row("s-started", "started", stamp(1))
    if started_at is DROP:
        del bad["started_at"]
    else:
        bad["started_at"] = started_at
    seed(world, [row("d0", "done", stamp(0)), bad])
    code, out = run(world, args_for(world))
    assert code == 1
    assert out["ok"] is False
    assert out["error"]["type"] == "AmBadOutput"
    message = out["error"]["message"]
    assert "am runs" in message and "started_at" in message
    assert "yesterday" not in message
    assert calls(world) == [LIST(str(world["proj"]))]


# --- the time window -------------------------------------------------------------

def test_before_is_strict(world):
    seed(world, [row("after", "done", "2026-10-09T00:00:01+00:00"),
                 row("equal", "done", "2026-10-09T00:00:00+00:00"),
                 row("just-before", "done", "2026-10-08T23:59:59.999999+00:00")])
    code, out = run(world, args_for(world))
    assert code == 0
    assert ids(out) == ["just-before"]


def test_before_compares_times_not_strings(world):
    # z is 15:00Z (later) but sorts first as a string; y is 14:00Z (earlier) but
    # sorts after --before as a string.
    seed(world, [row("z", "done", "2026-10-08T14:00:00-01:00"),
                 row("x", "done", "2026-10-08 14:38:23.739155+00:00"),
                 row("y", "done", "2026-10-08T16:00:00+02:00")])
    code, out = run(world, [str(world["proj"]), "--before", "2026-10-08T14:38:24Z"])
    assert code == 0
    assert ids(out) == ["x", "y"]


def test_naive_iso_is_utc(world):
    seed(world, [row("equal", "done", "2026-10-08T12:00:00+00:00"),
                 row("second-before", "done", "2026-10-08T11:59:59+00:00"),
                 row("plus-one", "done", "2026-10-08T12:30:00+01:00")])
    code, out = run(world, [str(world["proj"]), "--before", "2026-10-08T12:00:00"])
    assert code == 0
    assert ids(out) == ["second-before", "plus-one"]


def test_naive_started_at_is_utc(world):
    seed(world, [row("equal", "done", "2026-10-08T12:00:00"),
                 row("second-before", "done", "2026-10-08T11:59:59")])
    code, out = run(world, [str(world["proj"]), "--before", "2026-10-08T12:00:00+00:00"])
    assert code == 0
    assert ids(out) == ["second-before"]


def test_since_is_inclusive(world):
    seed(world, [row("after", "done", "2026-10-08T01:00:00+00:00"),
                 row("equal", "done", "2026-10-08T00:00:00+00:00"),
                 row("just-before", "done", "2026-10-07T23:59:59.999999+00:00")])
    code, out = run(world, args_for(world, "--since", "2026-10-08T00:00:00Z"))
    assert code == 0
    assert ids(out) == ["after", "equal"]


@pytest.mark.parametrize("since", ["2026-10-10T00:00:00Z", BEFORE], ids=["after", "equal"])
def test_since_after_before_is_empty(world, since):
    seed(world, rows(3))
    code, out = run(world, args_for(world, "--since", since))
    assert code == 0
    assert out == {"ok": True, "runs": [], "more": False}


# --- statuses --------------------------------------------------------------------

STATUSES = ["started", "done", "escalated", "stopped", "cancelled", "canceled"]


def test_default_status_is_terminal(world):
    statuses = STATUSES + ["failed"]
    seed(world, [row("s-" + s, s, stamp(i)) for i, s in enumerate(statuses)])
    code, out = run(world, args_for(world))
    assert code == 0
    assert ids(out) == ["s-" + s for s in TERMINAL]


@pytest.mark.parametrize("value, want", [
    ("cancelled", ["cancelled"]),
    ("canceled", ["canceled"]),
    ("cancelled,canceled", ["cancelled", "canceled"]),
    ("done,escalated", ["done", "escalated"]),
    ("started", ["started"]),
    ("done,done", ["done"]),
    ("nope", []),
], ids=["cancelled", "canceled", "both-spellings", "two", "non-terminal", "duplicate", "unknown"])
def test_status_filter(world, value, want):
    seed(world, [row("s-" + s, s, stamp(i)) for i, s in enumerate(STATUSES)])
    code, out = run(world, args_for(world, "--status", value))
    assert code == 0
    assert ids(out) == ["s-" + s for s in want]
    assert out["more"] is False


# --- page ------------------------------------------------------------------------

def test_default_limit_is_10_and_more(world):
    seed(world, rows(12))
    code, out = run(world, args_for(world))
    assert code == 0
    assert ids(out) == ["d%d" % i for i in range(10)]
    assert out["more"] is True
    seed(world, rows(10))
    code, out = run(world, args_for(world))
    assert code == 0
    assert ids(out) == ["d%d" % i for i in range(10)]
    assert out["more"] is False


def test_limit_caps_at_25(world):
    seed(world, rows(30))
    for limit in ["100", "9" * 5000]:
        code, out = run(world, args_for(world, "--limit", limit))
        assert code == 0
        assert ids(out) == ["d%d" % i for i in range(25)]
        assert out["more"] is True
    seed(world, rows(25))
    code, out = run(world, args_for(world, "--limit", "25"))
    assert code == 0
    assert len(out["runs"]) == 25
    assert out["more"] is False


def test_limit_smaller_than_page(world):
    seed(world, rows(3))
    code, out = run(world, args_for(world, "--limit", "2"))
    assert code == 0
    assert ids(out) == ["d0", "d1"]
    assert out["more"] is True


def test_kept_rows_only_count_toward_more(world):
    # Two kept rows and a dropped one with --limit 2: nothing kept is left over.
    seed(world, [row("d0", "done", stamp(0)), row("s0", "started", stamp(1)),
                 row("d1", "done", stamp(2))])
    code, out = run(world, args_for(world, "--limit", "2"))
    assert code == 0
    assert ids(out) == ["d0", "d1"]
    assert out["more"] is False


def test_empty_page(world):
    seed(world, rows(3, status="started"))
    code, out = run(world, args_for(world))
    assert code == 0
    assert out == {"ok": True, "runs": [], "more": False}
    assert calls(world) == [LIST(str(world["proj"]))]

# --- am status fan-out -------------------------------------------------------------

def expected(run, data):
    out = dict(run)
    out["status"] = data
    return out


def test_one_am_status_per_paged_row(world):
    root = str(world["proj"])
    seed(world, [row("s0", "started", stamp(0))]
         + [row("d%d" % i, "done", stamp(i + 1)) for i in range(4)])
    code, out = run(world, args_for(world, "--limit", "2"))
    assert code == 0
    made = calls(world)
    assert made == [LIST(root), STATUS("d0"), STATUS("d1")]
    assert not any("--repo-dir" in argv for argv in made[1:])


def test_output_shape(world):
    runs = rows(3)
    seed(world, runs)
    code, out = run(world, args_for(world))
    assert code == 0
    assert set(out) == {"ok", "runs", "more"}
    assert out == {"ok": True, "runs": [expected(r, status_data(r["id"])) for r in runs],
                   "more": False}


def test_am_status_envelope_passthrough_stops(world):
    # d1 has no status reply: the fake answers UnknownRunError, like real am.
    root = str(world["proj"])
    set_runs(world, rows(3))
    set_status(world, "d0", status_data("d0"))
    set_status(world, "d2", status_data("d2"))
    code, out = run(world, args_for(world))
    assert code == 1
    assert out == UNKNOWN_RUN
    assert calls(world) == [LIST(root), STATUS("d0"), STATUS("d1")]


def test_status_without_as_of_seq_is_schema_mismatch(world):
    root = str(world["proj"])
    set_runs(world, rows(2))
    # synthetic: the captured status data without its as_of_seq.
    data = status_data("d0")
    del data["as_of_seq"]
    set_status(world, "d0", data)
    set_status(world, "d1", status_data("d1"))
    code, out = run(world, args_for(world))
    assert code == 1
    assert out == {"ok": False, "error": {
        "type": "SchemaMismatch",
        "message": "am status d0 sent no non-negative integer as_of_seq; "
                   "the plugin needs the newer am."}}
    assert calls(world) == [LIST(root), STATUS("d0")]


def test_status_data_not_an_object_is_bad_output(world):
    root = str(world["proj"])
    set_runs(world, rows(2))
    # synthetic: an ok envelope whose data is null.
    set_status(world, "d0", None)
    code, out = run(world, args_for(world))
    assert code == 1
    assert out == {"ok": False, "error": {"type": "AmBadOutput",
                                          "message": "am status d0 data is not an object."}}
    assert calls(world) == [LIST(root), STATUS("d0")]
