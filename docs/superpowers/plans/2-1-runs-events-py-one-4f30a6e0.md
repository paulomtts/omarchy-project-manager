# 2.1 runs-events.py: one run's journal as one JSON line — design

Card `4f30a6e0`, a subtask of story `a22240f0` ("Events backend"). Parent spec:
`docs/superpowers/specs/2026-10-05-run-events-timeline-design.md` (below:
**parent**). Sibling: `830da24f` (2.2, the `am watch RUN` contract test in
`tests/contract/test_am_shapes.py`).

## Goal

A new one-shot helper, `core/backend/runs/runs-events.py`, that reads one run's
events through `am watch RUN [--since SEQ]` and prints exactly one JSON line
`{"ok": true, "events": [...], "last_seq": N, "total": M}`, optionally keeping
only the last N events (`--tail N`) so a long run's journal never reaches QML
whole. Every failure is one `{"ok": false, "error": {"type", "message"}}` line.

## Card vs parent: which command

The parent names `am events RUN [--after-seq] [--tail] [--before-seq] [--limit]`
with a `head` field (parent L44-49, L77-81). The card names `am watch RUN
[--since SEQ]` with `--tail` done by the helper, and the card governs. The
installed `am` (`am watch --help`) prints a run's events once, as one envelope
`{"ok": true, "data": {"events": [...]}}` (no `head`), in gseq order (for one
run that is also seq order), and `--since SEQ` keeps the events whose per-run
`seq` is **greater than** SEQ (default 0). `am watch` has no `--tail`, so the
helper slices. Paging backward (`--before-seq`), `--limit` and `head` are not
part of this helper.

## Inherited constraints

| constraint | source |
|---|---|
| Thin passthrough of the documented `am` command; one JSON line; a long run's events never cross into QML whole | parent L77-81, L161 |
| No `--repo-dir`: am resolves the run by id | parent L44, card |
| No second `am watch --follow` process; a one-shot read only | parent L38, card |
| The plugin never reads am's files or database | parent L37 |
| An am refusal or failure is `{ok:false, error:{type,message}}`; exit 0 either way | parent L79-81, card |
| `UnknownRunError` is passed through (the store shows the empty state) | parent L156 |
| am exit 3 without a refusal envelope (store unreadable) is its own error | parent L157; type name `CorruptJournal` as `core/backend/runs/runs-watch.py:256-270` |
| Each event is `{seq, gseq, ts, run_id, event, story, card, phase, attempt, payload}`; unknown events and keys are not the helper's concern | parent L51-55, L62; `tests/fixtures/am/watch-events.json` |
| Backend pytest with a stub am: argv, refusal passthrough, missing am, store unreadable | parent L170-171, card |
| `AmMissing` exit 0; a 60 s timeout is `HelperError`; argv lists only | card |
| `docs/architecture.md` layering; `tests/architecture` passes (no duplicated `emit`, etc.: `tests/architecture/test_layers.py:231`) | card |
| Docstrings and comments state the contract only, no narrative | card |
| `bash tests/run.sh` green; tests first | card |

Model: `core/backend/runs/runs-logs.py` (structure: `USAGE`, `AM_TIMEOUT = 60`,
`failure`, `envelope_of`, `main`, `guarded`, `emit` from `common/json_line`)
and its test `tests/core/backend/runs/test_runs_logs.py` (fake am harness).
File-local `failure`/`envelope_of` copies are allowed (several helpers already
have them; the duplicate guard lists only `emit`, `inside`, `write_atomic`,
`split_frontmatter`, `frontmatter_of`).

## Behavior

Command line: `runs-events.py RUN [--since SEQ] [--tail N]`.

1. **Usage.** Exit 2 with exactly one line
   `{"ok": false, "error": {"type": "Usage", "message": "usage: runs-events.py RUN [--since SEQ] [--tail N]"}}`,
   am not looked up and not run, when: there is no RUN; RUN is empty or starts
   with `-`; there is a second positional argument; an option other than
   `--since` / `--tail` appears; an option is given twice or has no value;
   SEQ is not one or more ASCII digits (`0` allowed); N is not one or more
   ASCII digits or is `0`. Options may come in either order, after RUN.
   (Validating SEQ matters: real am answers `--since -1` with a `CliError`
   envelope and `--since abc` with click usage text at exit 2.)
2. **am's argv.** am is run once, with exactly `["watch", RUN]` after the
   executable, plus `["--since", SEQ]` when `--since` was given (SEQ verbatim
   as typed). Never `--follow`, `--repo-dir`, `--all`, `--since-seq`,
   `--pretty`. `--tail` never reaches am.
3. **Process.** `shutil.which("am")`, then `subprocess.run` with an argv list
   (no shell; RUN with spaces or `;`/`$(...)` reaches am as one element,
   unchanged), stdin `/dev/null`, stdout/stderr captured, 60 s timeout
   (`AM_TIMEOUT = 60`, module-level).
4. **Success.** am's stdout is a JSON object with `ok: true` (whatever am's
   exit code — the envelope's `ok` decides, as runs-logs), `data` an object,
   `data.events` a list whose every element is an object with an integer `seq`
   (a JSON bool is not an integer). Then, with `matched = data.events` in am's
   order:
   - `total` = `len(matched)`;
   - `events` = `matched[-N:]` with `--tail N`, else all of `matched`; each
     event object unchanged (all keys, unknown ones included);
   - `last_seq` = the highest `seq` of **all** of `matched` (not only the
     returned ones); with no matched events, the `--since` value as an integer,
     or `0` without `--since` — so a caller can always pass `last_seq` back as
     `--since`.
   Printed as `{"ok": true, "events": [...], "last_seq": N, "total": M}`
   (exactly these four keys), exit 0. Pretty-printed or multi-line am output
   still yields one line.
5. **Refusal passthrough.** am's stdout is a JSON object with `ok: false`:
   printed unchanged as one line, exit 0, whatever am's exit code (real am:
   `UnknownRunError` at exit 3; `StoreBusyError` likewise passes through as
   itself).
6. **Corrupt journal.** am exits 3 and its stdout is not a JSON object with a
   boolean `ok` (empty, text, a traceback): `{"ok": false, "error": {"type":
   "CorruptJournal", "message": <am's stderr stripped, or "am watch exited 3."
   when empty>}}`, exit 0.
7. **Other failed exit without an envelope.** am exits non-zero (not 3) and
   stdout is not a JSON object with a boolean `ok`: `{"type": "AmBadOutput",
   "message": ...}`, exit 0; the message contains `am watch` and `(exit N)`.
8. **Bad output at exit 0.** am exits 0 and stdout is not JSON, not an object,
   has no boolean `ok`, or is `ok: true` with a missing/non-object `data`, a
   missing/non-list `data.events`, or an event that is not an object or has no
   integer `seq`: `AmBadOutput`, message contains `am watch` and `(exit 0)`.
9. **am missing.** `{"ok": false, "error": {"type": "AmMissing", "message": "am is not installed."}}`, exit 0.
10. **Catch-all.** Any other exception (`subprocess.TimeoutExpired`, an am that
    cannot start) is `{"type": "HelperError", "message": "The events snapshot
    failed: " + reason}`, exit 0 (the `guarded` pattern of runs-logs; SystemExit
    is re-raised).
11. **One line, always.** Every path prints exactly one JSON line on stdout.
    Exit 0 on every path but Usage (exit 2).

### Contract text

- Module docstring states the usage line, the am argv (rule 2), the output
  shape and the meaning of `total`, `last_seq` (rule 4), and each error type
  with its trigger (rules 5-10), in the runs-logs docstring style.
- `docs/architecture.md:196`: after the `runs-logs.py` sentence, add one
  sentence: `` `runs-events.py RUN [--since SEQ] [--tail N]` is a one-shot `am watch RUN [--since SEQ]` read (no `--follow`, no `--repo-dir`) that prints `{ok, events, last_seq, total}` -- `total` the matched count, `events` at most the last N with `--tail`, `last_seq` the highest `seq` of every matched event (the `--since` value, or 0, when none) -- or `{ok: false, error}`: am's refusal unchanged, `CorruptJournal` (am exit 3 without an envelope), `AmBadOutput`, `AmMissing`, `HelperError` (60 s timeout); `Usage` exits 2, every other path 0. `` and change "All three use only documented `am` commands" to "All of them use only …". Nothing else in the doc.

## Tests

All in the new `tests/core/backend/runs/test_runs_events.py`. Tier: pytest
backend helper, hermetic — a fake `am` on a temp PATH (the `FAKE_AM` script of
`test_runs_logs.py`, keyed on subcommand `watch`: files `watch.out`,
`watch.code`, `watch.err`, argv appended to `calls.log`; a missing `watch.out`
answers like real am for an unknown run: `UnknownRunError` envelope, exit 3),
temp HOME / XDG_DATA_HOME. Why this tier: the deliverable is a subprocess
wrapper whose observables are the argv it hands am and the line it prints; the
fake am records the first and serves the second, with no QML, store or real am.
Real am output comes from `tests/fixtures/am/watch-events.json` (`json.load`,
`_note` stripped; 60 events of one run, seq 1-60); any hand-written payload is
labelled `synthetic:`. Timeouts use the runs-logs pattern: load the script with
`importlib`, monkeypatch `AM_TIMEOUT` to 0.5, call `guarded`.

1. `test_fixture_is_one_run_in_seq_order` — guards the fixture assumptions the
   tests rely on (60 events, one `run_id`, seqs strictly increasing).
2. `test_argv_without_since` — `["watch", RUN]` exactly; no `--follow`,
   `--repo-dir`, `--pretty`.
3. `test_argv_with_since` — `RUN --since 12` → `["watch", RUN, "--since", "12"]`;
   also `--since 0`.
4. `test_tail_is_not_passed_to_am` — `RUN --tail 5 --since 3` (either order)
   → `["watch", RUN, "--since", "3"]`.
5. `test_all_events_without_tail` — output is `{"ok": true, "events":
   <fixture events>, "last_seq": 60, "total": 60}`, events unchanged.
6. `test_tail_keeps_last_n_and_counts_all` — `--tail 5`: events are the last
   five fixture events in order, `total` 60, `last_seq` 60.
7. `test_tail_larger_than_match` — `--tail 500`: all 60, `total` 60.
8. `test_last_seq_is_max_over_all_matched` — synthetic: events whose highest
   seq is not the last one returned by the tail (e.g. am order `[.., seq 9,
   seq 7]` with `--tail 1`) → `last_seq` 9, events `[seq 7]`.
9. `test_empty_match_last_seq` — synthetic `{"ok": true, "data": {"events":
   []}}`: with `--since 42` → `last_seq` 42, `total` 0, `events` []; without
   `--since` → `last_seq` 0.
10. `test_unknown_event_keys_pass_through` — synthetic event with an extra key
    and an unknown `event` kind comes out unchanged.
11. `test_refusal_passthrough` (parametrized: `UnknownRunError` at exit 3 —
    the fake's missing-fixture default — and synthetic `StoreBusyError` at
    exit 3, `CliError` at exit 0) → printed unchanged, exit 0.
12. `test_corrupt_journal_exit_3` (parametrized: empty stdout, plain text,
    traceback; with and without stderr) → `CorruptJournal`, message is the
    stripped stderr or `am watch exited 3.`, exit 0.
13. `test_other_nonzero_without_envelope_is_bad_output` — exit 1 / exit 2 with
    text → `AmBadOutput`, message contains `am watch` and `(exit N)`.
14. `test_bad_output_at_exit_0` (parametrized: not JSON, list, no `ok`, `ok`
    a string, `ok: true` without `data`, `data.events` not a list, an event
    without `seq`, `seq` a string, `seq` a bool) → `AmBadOutput`, `(exit 0)`.
15. `test_am_missing` — PATH to an empty dir → `AmMissing`, exit 0.
16. `test_usage` (parametrized: none, empty RUN, RUN `-x`, two positionals,
    unknown option, `--since` without value, `--since -1`, `--since abc`,
    `--tail 0`, `--tail x`, `--since` twice) → exact Usage line, exit 2,
    `calls(world) == []`.
17. `test_run_reaches_am_verbatim` — RUN `r 1; echo $(id) & x` is one argv
    element, unchanged.
18. `test_am_does_not_inherit_stdin` — runs-logs' Popen pattern: an am that
    reads stdin gets EOF; helper exits 0 with one line.
19. `test_pretty_output_is_one_line` — fixture envelope written with
    `indent=2` → one line, same payload.
20. `test_am_cannot_start_is_helper_error` — `#!/nonexistent/interpreter` →
    `HelperError`, message starts `The events snapshot failed: `.
21. `test_am_timeout_is_helper_error` — `AM_TIMEOUT == 60`; patched to 0.5 with
    a sleeping am → `HelperError`, one line, exit 0.

Suite gate: `bash tests/run.sh` green, including `tests/architecture`.

## Out of scope

- `tests/contract/test_am_shapes.py` and the real `am watch RUN` shape: card
  `830da24f` (2.2).
- `RunStore.qml` events state, `EventsPane.qml`, Run detail wiring, the `e`
  key, filters, `core/domain/runEvents.js` (story "Events domain", done, and
  later stories of the parent).
- `am events`, `--before-seq`, `--after-seq`, `--limit`, `head`, gseq cursors
  (parent L44-49, L77-81; the card replaced them).
- Any change to `runs-logs.py`, `runs-watch.py`, `common/`; README.

# runs-events.py: one run's journal as one JSON line Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `core/backend/runs/runs-events.py RUN [--since SEQ] [--tail N]`, a one-shot `am watch RUN [--since SEQ]` read that prints exactly one JSON line `{"ok": true, "events", "last_seq", "total"}` or one `{"ok": false, "error"}` line.

**Architecture:** One stdlib-only script modelled on `core/backend/runs/runs-logs.py`: `parse_args` → `shutil.which("am")` → `subprocess.run` with an argv list → `envelope_of` (shape check) → `events_of` (data/events/seq check) → `snapshot` (tail, total, last_seq) → `emit` from `common/json_line`. `guarded` turns any unexpected exception into `HelperError`. Task 1 delivers argv parsing and the success path; Task 2 adds every error path and the `docs/architecture.md` sentence.

**Tech Stack:** Python 3 stdlib (`json`, `os`, `shutil`, `subprocess`, `sys`), pytest with a fake `am` on a temp PATH.

**Spec:** `docs/superpowers/specs/2-1-runs-events-py-one-4f30a6e0.md` (prepended above this plan).

## Global Constraints

- New files only: `core/backend/runs/runs-events.py`, `tests/core/backend/runs/test_runs_events.py`; the one other edit is `docs/architecture.md:196` (Task 2). No change to `runs-logs.py`, `runs-watch.py`, `common/`, README, `tests/contract/`.
- `from common.json_line import emit` via the `sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))` line; never define `emit`, `inside`, `write_atomic`, `split_frontmatter`, `frontmatter_of` (`tests/architecture/test_layers.py:231`). File-local `failure` / `envelope_of` are allowed.
- `USAGE = "usage: runs-events.py RUN [--since SEQ] [--tail N]"`; `AM_TIMEOUT = 60` at module level.
- am argv after the executable: exactly `["watch", RUN]` plus `["--since", SEQ]` when given (SEQ verbatim). Never `--follow`, `--repo-dir`, `--all`, `--since-seq`, `--pretty`; `--tail` never reaches am.
- `subprocess.run` with an argv list, `capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=AM_TIMEOUT`; no shell.
- Exactly one JSON line on stdout on every path; exit 2 for `Usage` only, exit 0 on every other path.
- Error types and messages: `Usage` (the USAGE line), `AmMissing` (`am is not installed.`), `CorruptJournal` (am's stderr stripped, or `am watch exited 3.`), `AmBadOutput` (message contains `am watch` and `(exit N)`), `HelperError` (`The events snapshot failed: ` + reason).
- The plugin never reads am's files or database; only `am watch` is run.
- Docstrings and comments state the contract only, no narrative.
- Every hand-written am payload in a test carries a `# synthetic:` comment; real data comes from `tests/fixtures/am/watch-events.json` with `_note` stripped.
- `python3` here has no pytest: run tests as `uv run --with pytest python3 -m pytest ...` (what `tests/run.sh` falls back to). Suite gate: `bash tests/run.sh` green, including `tests/architecture`.

## Review Focus

1. Non-ASCII digits (`--since ٣`, `--tail ²`): `str.isdigit()` accepts them and `int()` may too, so a careless check passes them to am — expected `Usage`, exit 2, am not run. Pinned in Task 1 `test_usage` (ids `since-arabic-digit`, `tail-superscript`).
2. `--opt=value` form and `--tail 00`: a person may type `--since=5` or a zero with leading zeros — expected `Usage` for both, never a positional or a zero tail. Pinned in Task 1 `test_usage` (ids `since-equals`, `tail-double-zero`).
3. `--since 007` (leading zeros): SEQ reaches am verbatim as `"007"` and an empty match reports `last_seq` 7 (an integer), so it can be passed back. Pinned in Task 1 `test_since_leading_zeros`.
4. A huge `--tail` (`99999999999999999999`) must not overflow or crash: all events, `total` 60. Pinned in Task 1 `test_tail_larger_than_match` (parametrized).
5. am exits 3 (or 1) with a valid `ok: true` envelope and stderr noise: the envelope decides, so the result is the snapshot, never `CorruptJournal`, and stderr never reaches stdout; a refusal at exit 3 with stderr text stays a passthrough. Pinned in Task 2 `test_ok_wins_over_exit_code_and_stderr` and `test_refusal_with_stderr_is_not_corrupt`.

---

### Task 1: argv parsing, am's argv and the success snapshot

**Files:**
- Create: `core/backend/runs/runs-events.py`
- Create: `tests/core/backend/runs/test_runs_events.py`

**Interfaces:**
- Consumes: `common.json_line.emit(payload, code=0) -> int` (prints `json.dumps(payload)`, returns `code`); `tests/fixtures/am/watch-events.json` (`{"_note", "ok": true, "data": {"events": [60 events, seq 1..60, one run_id]}}`).
- Produces (module `runs-events.py`): `USAGE: str`, `AM_TIMEOUT = 60`, `failure(kind, message, code=0) -> int`, `parse_args(argv: list[str]) -> tuple[str, str | None, int | None] | None` (run, since digit-string, tail int ≥ 1), `watch_argv(run: str, since: str | None) -> list[str]`, `snapshot(events: list[dict], since: str | None, tail: int | None) -> dict`, `main(argv: list[str]) -> int`. Test helpers in `test_runs_events.py` used by Task 2: `FAKE_AM`, `SCRIPT`, `RUN`, `UNKNOWN_RUN`, `fixture(name)`, `watch_envelope()`, `watch_events()`, `write_exec(path, text)`, `world` fixture, `env_for(world, drop=(), **extra)`, `run(world, args=None, drop=(), **extra) -> (exit, payload)`, `set_watch(world, envelope, code=0)`, `set_raw(world, text, code=0, stderr=None)`, `calls(world) -> list[list[str]]`.

- [ ] **Step 1: Write the failing tests**

Create `tests/core/backend/runs/test_runs_events.py`:

```python
"""runs-events.py: one run's events through a one-shot `am watch RUN`, one JSON line on every path.

Hermetic: a fake `am` lives on a temp PATH and serves, from FAKE_AM_DIR, the
committed capture tests/fixtures/am/watch-events.json (a payload no capture holds
is labelled `synthetic:`), appending each call's argv to calls.log; HOME and
XDG_DATA_HOME are temp. The real `am` and real data are never touched.
"""
import importlib.util
import json
import os
import stat
import subprocess
import sys

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..", "..", "..")
SCRIPT = os.path.join(ROOT, "core", "backend", "runs", "runs-events.py")

# The fake am logs its argv, then (keyed on the subcommand, so "watch") writes
# FAKE_AM_DIR/watch.err to stderr if present, prints FAKE_AM_DIR/watch.out verbatim
# and exits with FAKE_AM_DIR/watch.code (default 0). A missing .out fixture behaves
# like real am for an unknown run: an UnknownRunError envelope and exit 3.
FAKE_AM = '''#!/usr/bin/env python3
import json, os, sys
d = os.environ["FAKE_AM_DIR"]
args = sys.argv[1:]
with open(os.path.join(d, "calls.log"), "a") as f:
    f.write(json.dumps(args) + "\\n")
name = "watch" if args[:1] == ["watch"] else "other"
out = os.path.join(d, name + ".out")
if not os.path.exists(out):
    sys.stdout.write(json.dumps({"error": {"message": "unknown run", "type": "UnknownRunError"}, "ok": False}) + "\\n")
    sys.exit(3)
err = os.path.join(d, name + ".err")
if os.path.exists(err):
    with open(err) as f:
        sys.stderr.write(f.read())
with open(out) as f:
    sys.stdout.write(f.read())
code = os.path.join(d, name + ".code")
sys.exit(int(open(code).read()) if os.path.exists(code) else 0)
'''

RUN = "20261008T143807Z-63060df3"
FIXTURES = os.path.join(ROOT, "tests", "fixtures", "am")
USAGE_LINE = {"ok": False, "error": {
    "type": "Usage", "message": "usage: runs-events.py RUN [--since SEQ] [--tail N]"}}
# synthetic: am's error envelope for an unknown run; no capture holds one.
UNKNOWN_RUN = {"error": {"message": "unknown run", "type": "UnknownRunError"}, "ok": False}


def fixture(name):
    """A fresh json.load of tests/fixtures/am/<name>, so an edit never reaches
    another call."""
    with open(os.path.join(FIXTURES, name)) as f:
        return json.load(f)


def watch_envelope():
    """The captured `am watch RUN` envelope without the capture's `_note`."""
    return {k: v for k, v in fixture("watch-events.json").items() if not k.startswith("_")}


def watch_events():
    """The captured run's 60 events, seq 1..60, in am's order."""
    return watch_envelope()["data"]["events"]


def write_exec(path, text):
    path.write_text(text)
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


@pytest.fixture
def world(tmp_path):
    """A temp PATH with a fake am, its fixture dir and a temp HOME/XDG_DATA_HOME."""
    bindir = tmp_path / "bin"
    bindir.mkdir()
    write_exec(bindir / "am", FAKE_AM)
    amdir = tmp_path / "am"
    amdir.mkdir()
    home = tmp_path / "home"
    home.mkdir()
    return {"tmp": tmp_path, "bin": bindir, "am": amdir, "home": home,
            "data": tmp_path / "data"}


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


def run(world, args=None, drop=(), **extra):
    """Run the helper; assert stdout is exactly one JSON line; return (exit, payload)."""
    argv = [RUN] if args is None else args
    p = subprocess.run([sys.executable, SCRIPT, *argv], capture_output=True, text=True,
                       env=env_for(world, drop, **extra), timeout=60)
    lines = p.stdout.splitlines()
    assert len(lines) == 1, (p.stdout, p.stderr)
    return p.returncode, json.loads(lines[0])


def set_watch(world, envelope, code=0):
    (world["am"] / "watch.out").write_text(json.dumps(envelope) + "\n")
    (world["am"] / "watch.code").write_text(str(code))


def set_raw(world, text, code=0, stderr=None):
    (world["am"] / "watch.out").write_text(text)
    (world["am"] / "watch.code").write_text(str(code))
    if stderr is not None:
        (world["am"] / "watch.err").write_text(stderr)


def calls(world):
    log = world["am"] / "calls.log"
    return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []


def event(seq, **extra):
    """synthetic: one journal event of RUN with the given seq."""
    e = {"seq": seq, "gseq": 100 + seq, "ts": "2026-10-08T14:38:07Z", "run_id": RUN,
         "event": "phase_upsert", "story": None, "card": None, "phase": None,
         "attempt": None, "payload": {}}
    e.update(extra)
    return e


# --- fixture and am's argv ------------------------------------------------------

def test_fixture_is_one_run_in_seq_order():
    events = watch_events()
    assert watch_envelope()["ok"] is True
    assert len(events) == 60
    assert {e["run_id"] for e in events} == {RUN}
    seqs = [e["seq"] for e in events]
    assert seqs == sorted(set(seqs))
    assert seqs[0] == 1 and seqs[-1] == 60


def test_argv_without_since(world):
    set_watch(world, watch_envelope())
    code, _ = run(world, [RUN])
    assert code == 0
    made = calls(world)
    assert made == [["watch", RUN]]
    for flag in ("--follow", "--repo-dir", "--pretty", "--all", "--since-seq"):
        assert flag not in made[0]


@pytest.mark.parametrize("seq", ["12", "0"])
def test_argv_with_since(world, seq):
    set_watch(world, watch_envelope())
    code, _ = run(world, [RUN, "--since", seq])
    assert code == 0
    assert calls(world) == [["watch", RUN, "--since", seq]]


@pytest.mark.parametrize("args", [
    [RUN, "--tail", "5", "--since", "3"],
    [RUN, "--since", "3", "--tail", "5"],
], ids=["tail-first", "since-first"])
def test_tail_is_not_passed_to_am(world, args):
    set_watch(world, watch_envelope())
    code, _ = run(world, args)
    assert code == 0
    assert calls(world) == [["watch", RUN, "--since", "3"]]


def test_since_leading_zeros(world):
    # SEQ reaches am as typed; an empty match still reports it as an integer.
    # synthetic: am's envelope when no event is newer than --since.
    set_watch(world, {"ok": True, "data": {"events": []}})
    code, out = run(world, [RUN, "--since", "007"])
    assert code == 0
    assert calls(world) == [["watch", RUN, "--since", "007"]]
    assert out == {"ok": True, "events": [], "last_seq": 7, "total": 0}


def test_run_reaches_am_verbatim(world):
    run_id = "r 1; echo $(id) & x"
    set_watch(world, watch_envelope())
    code, _ = run(world, [run_id])
    assert code == 0
    assert calls(world) == [["watch", run_id]]


# --- the snapshot ----------------------------------------------------------------

def test_all_events_without_tail(world):
    set_watch(world, watch_envelope())
    code, out = run(world)
    assert code == 0
    assert out == {"ok": True, "events": watch_events(), "last_seq": 60, "total": 60}
    assert list(out) == ["ok", "events", "last_seq", "total"]


def test_tail_keeps_last_n_and_counts_all(world):
    set_watch(world, watch_envelope())
    code, out = run(world, [RUN, "--tail", "5"])
    assert code == 0
    assert out == {"ok": True, "events": watch_events()[-5:], "last_seq": 60, "total": 60}
    assert [e["seq"] for e in out["events"]] == [56, 57, 58, 59, 60]


@pytest.mark.parametrize("tail", ["500", "60", "99999999999999999999"])
def test_tail_larger_than_match(world, tail):
    set_watch(world, watch_envelope())
    code, out = run(world, [RUN, "--tail", tail])
    assert code == 0
    assert out == {"ok": True, "events": watch_events(), "last_seq": 60, "total": 60}


def test_last_seq_is_max_over_all_matched(world):
    # synthetic: am order whose highest seq is not the last event.
    set_watch(world, {"ok": True, "data": {"events": [event(5), event(9), event(7)]}})
    code, out = run(world, [RUN, "--tail", "1"])
    assert code == 0
    assert out == {"ok": True, "events": [event(7)], "last_seq": 9, "total": 3}


@pytest.mark.parametrize("args,last_seq", [
    ([RUN, "--since", "42"], 42),
    ([RUN], 0),
    ([RUN, "--since", "42", "--tail", "3"], 42),
], ids=["since", "no-since", "since-and-tail"])
def test_empty_match_last_seq(world, args, last_seq):
    # synthetic: am's envelope when no event matched.
    set_watch(world, {"ok": True, "data": {"events": []}})
    code, out = run(world, args)
    assert code == 0
    assert out == {"ok": True, "events": [], "last_seq": last_seq, "total": 0}


def test_unknown_event_keys_pass_through(world):
    # synthetic: an event kind and a key no capture holds.
    odd = event(3, event="brand_new_kind", extra_key={"nested": [1, "two"]})
    set_watch(world, {"ok": True, "data": {"events": [event(2), odd]}})
    code, out = run(world)
    assert code == 0
    assert out["events"] == [event(2), odd]
    assert out["last_seq"] == 3 and out["total"] == 2


def test_pretty_output_is_one_line(world):
    set_raw(world, json.dumps(watch_envelope(), indent=2) + "\n")
    code, out = run(world)  # run() asserts exactly one line
    assert code == 0
    assert out == {"ok": True, "events": watch_events(), "last_seq": 60, "total": 60}


def test_am_does_not_inherit_stdin(world):
    # The helper's stdin is an open pipe that never sends EOF. An am that reads
    # stdin must get EOF at once (stdin is /dev/null), not block on that pipe.
    set_watch(world, watch_envelope())
    write_exec(world["bin"] / "am",
               "#!/usr/bin/env python3\nimport os, sys\nsys.stdin.read()\n"
               "sys.stdout.write(open(os.path.join(os.environ['FAKE_AM_DIR'], 'watch.out')).read())\n")
    p = subprocess.Popen([sys.executable, SCRIPT, RUN], stdin=subprocess.PIPE,
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                         env=env_for(world))
    try:
        code = p.wait(timeout=15)
    except subprocess.TimeoutExpired:
        p.kill()
        p.wait()
        pytest.fail("am blocked reading the helper's stdin")
    finally:
        p.stdin.close()
    lines = p.stdout.read().splitlines()
    p.stdout.close()
    p.stderr.close()
    assert code == 0
    assert len(lines) == 1
    assert json.loads(lines[0]) == {"ok": True, "events": watch_events(),
                                    "last_seq": 60, "total": 60}


# --- usage -----------------------------------------------------------------------

@pytest.mark.parametrize("args", [
    [],
    [""],
    ["-x"],
    ["--since", "3", RUN],
    [RUN, "other"],
    [RUN, "--bogus", "1"],
    [RUN, "--since"],
    [RUN, "--tail"],
    [RUN, "--since", "-1"],
    [RUN, "--since", "abc"],
    [RUN, "--since", ""],
    [RUN, "--since", "1.5"],
    [RUN, "--since", " 3"],
    [RUN, "--since", "٣"],
    [RUN, "--since=5"],
    [RUN, "--tail", "0"],
    [RUN, "--tail", "00"],
    [RUN, "--tail", "x"],
    [RUN, "--tail", "-3"],
    [RUN, "--tail", "²"],
    [RUN, "--since", "1", "--since", "2"],
    [RUN, "--tail", "1", "--tail", "2"],
    [RUN, "--since", "--tail", "5"],
], ids=["none", "empty-run", "dash-run", "option-before-run", "two-positionals",
        "unknown-option", "since-no-value", "tail-no-value", "since-negative",
        "since-abc", "since-empty", "since-float", "since-space", "since-arabic-digit",
        "since-equals", "tail-zero", "tail-double-zero", "tail-x", "tail-negative",
        "tail-superscript", "since-twice", "tail-twice", "since-value-is-flag"])
def test_usage(world, args):
    set_watch(world, watch_envelope())
    code, out = run(world, args)
    assert code == 2
    assert out == USAGE_LINE
    assert calls(world) == []
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_events.py -q`
Expected: `test_fixture_is_one_run_in_seq_order` PASSES (it only reads the fixture); every other test FAILS — the script does not exist, so `python3 .../runs-events.py` prints nothing to stdout and `run()`'s `assert len(lines) == 1` fails.

- [ ] **Step 3: Write the minimal implementation**

Create `core/backend/runs/runs-events.py`:

```python
#!/usr/bin/env python3
"""One run's events snapshot: a one-shot `am watch RUN` read.

    runs-events.py RUN [--since SEQ] [--tail N]

Runs `am watch RUN`, plus `--since SEQ` when given (SEQ verbatim), as an argv
list (no shell, stdin /dev/null, 60 s timeout); never `--follow`, `--repo-dir`,
`--all`, `--since-seq` or `--pretty`. am resolves RUN by id. `--tail` never
reaches am.

Prints exactly one JSON line:
- {"ok": true, "events": [...], "last_seq": N, "total": M}: `total` is the
  number of events am printed; `events` are those events in am's order, each
  unchanged, only the last N with `--tail N`; `last_seq` is the highest `seq`
  of every event am printed, or the `--since` value (0 without it) when there
  are none, so it can always be passed back as `--since`;
- {"ok": false, "error": {"type": "Usage", ...}} for any other argv: no RUN, an
  empty or `-`-prefixed RUN, a second positional, an unknown, repeated or
  valueless option, a SEQ that is not ASCII digits, an N that is not ASCII
  digits or is 0.
Exit 0 whenever a line was printed; exit 2 for Usage only. Only the documented
`am watch` command is used; am's database and on-disk layout are never read.
"""
import json
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.json_line import emit  # noqa: E402

USAGE = "usage: runs-events.py RUN [--since SEQ] [--tail N]"
AM_TIMEOUT = 60
OPTIONS = ("--since", "--tail")


def failure(kind, message, code=0):
    return emit({"ok": False, "error": {"type": kind, "message": message}}, code)


def ascii_digits(text):
    """True for one or more ASCII digits."""
    return text.isascii() and text.isdigit()


def parse_args(argv):
    """(run, since, tail): since a digit string or None, tail an int of 1 or more
    or None; None for any argv the usage line does not allow."""
    if not argv or argv[0] == "" or argv[0].startswith("-"):
        return None
    options = {}
    rest = list(argv[1:])
    while rest:
        flag = rest.pop(0)
        if flag not in OPTIONS or flag in options or not rest:
            return None
        options[flag] = rest.pop(0)
    since = options.get("--since")
    tail = options.get("--tail")
    if since is not None and not ascii_digits(since):
        return None
    if tail is not None and not (ascii_digits(tail) and int(tail) > 0):
        return None
    return argv[0], since, None if tail is None else int(tail)


def watch_argv(run, since):
    """am's argv after the executable: the run, then --since SEQ when given."""
    return ["watch", run] + ([] if since is None else ["--since", since])


def snapshot(events, since, tail):
    """The success line for am's events; see the module docstring."""
    floor = 0 if since is None else int(since)
    return {
        "ok": True,
        "events": events if tail is None else events[-tail:],
        "last_seq": max((event["seq"] for event in events), default=floor),
        "total": len(events),
    }


def main(argv):
    parsed = parse_args(argv)
    if parsed is None:
        return failure("Usage", USAGE, 2)
    run, since, tail = parsed
    am = shutil.which("am")
    proc = subprocess.run([am, *watch_argv(run, since)], capture_output=True, text=True,
                          stdin=subprocess.DEVNULL, timeout=AM_TIMEOUT)
    envelope = json.loads(proc.stdout)
    return emit(snapshot(envelope["data"]["events"], since, tail))


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
```

Note: `ascii_digits` uses `str.isascii()` first because `str.isdigit()` alone accepts `"٣"` and `"²"` (Review Focus 1).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_events.py -q`
Expected: all PASS.

Run: `uv run --with pytest python3 -m pytest tests/architecture -q`
Expected: all PASS (no second `def emit(`).

- [ ] **Step 5: Commit**

```bash
git add core/backend/runs/runs-events.py tests/core/backend/runs/test_runs_events.py
git commit -m "feat(runs-events): one am watch RUN read as one events line, with --since and --tail"
```

---

### Task 2: error paths and the architecture doc

**Files:**
- Modify: `core/backend/runs/runs-events.py` (module docstring; add `BadOutput`, `is_int`, `envelope_of`, `events_of`, `guarded`; replace `main` and the `__main__` block)
- Modify: `tests/core/backend/runs/test_runs_events.py` (append tests at the end of the file)
- Modify: `docs/architecture.md:196` (one sentence added after the `runs-logs.py` sentence; "All three use" → "All of them use")

**Interfaces:**
- Consumes (from Task 1): `failure(kind, message, code=0) -> int`, `parse_args`, `watch_argv`, `snapshot(events, since, tail) -> dict`, `USAGE`, `AM_TIMEOUT`; test helpers `world`, `run`, `set_watch`, `set_raw`, `calls`, `env_for`, `write_exec`, `watch_envelope`, `watch_events`, `UNKNOWN_RUN`, `RUN`, `SCRIPT`.
- Produces: `BadOutput(Exception)`, `is_int(value) -> bool`, `envelope_of(stdout: str, returncode: int) -> dict`, `events_of(envelope: dict, returncode: int) -> list[dict]`, `main(argv) -> int` (final), `guarded(argv) -> int` (the script's entry point).

- [ ] **Step 1: Write the failing tests**

Append to the end of `tests/core/backend/runs/test_runs_events.py`:

```python


# --- am's refusal, corrupt journal, bad output -----------------------------------

# synthetic: am refusals other than the fake's UnknownRunError default.
STORE_BUSY = {"ok": False, "error": {"type": "StoreBusyError", "message": "store is busy"}}
CLI_ERROR = {"ok": False, "error": {"type": "CliError", "message": "--since must be >= 0"}}


@pytest.mark.parametrize("envelope,exit_code", [
    (None, 3),
    (STORE_BUSY, 3),
    (CLI_ERROR, 0),
], ids=["unknown-run-default", "store-busy", "cli-error-exit-0"])
def test_refusal_passthrough(world, envelope, exit_code):
    if envelope is None:
        expected = UNKNOWN_RUN  # no watch.out: the fake answers UnknownRunError, exit 3
    else:
        set_watch(world, envelope, code=exit_code)
        expected = envelope
    code, out = run(world)
    assert code == 0
    assert out == expected
    assert calls(world) == [["watch", RUN]]


def test_refusal_with_stderr_is_not_corrupt(world):
    # synthetic: a refusal at exit 3 with stderr noise stays am's refusal.
    (world["am"] / "watch.err").write_text("warning: noisy\n")
    set_watch(world, STORE_BUSY, code=3)
    code, out = run(world)
    assert code == 0
    assert out == STORE_BUSY


def test_ok_wins_over_exit_code_and_stderr(world):
    # The envelope's `ok` decides, not am's exit code; am's stderr never reaches
    # the helper's stdout line.
    for exit_code in (3, 1):
        # synthetic: am stderr noise.
        set_raw(world, json.dumps(watch_envelope()) + "\n", code=exit_code,
                stderr="warning: noisy\nmore noise\n")
        code, out = run(world, [RUN, "--tail", "2"])
        assert code == 0
        assert out == {"ok": True, "events": watch_events()[-2:], "last_seq": 60, "total": 60}


# synthetic: am exit 3 output that is not an envelope.
@pytest.mark.parametrize("text", [
    "",
    "store unreadable\n",
    "Traceback (most recent call last):\n  sqlite3.DatabaseError: file is not a database\n",
], ids=["empty", "text", "traceback"])
@pytest.mark.parametrize("stderr,message", [
    (None, "am watch exited 3."),
    ("", "am watch exited 3."),
    ("  journal is corrupt\n\n", "journal is corrupt"),
], ids=["no-stderr", "empty-stderr", "stderr"])
def test_corrupt_journal_exit_3(world, text, stderr, message):
    set_raw(world, text, code=3, stderr=stderr)
    code, out = run(world)
    assert code == 0
    assert out == {"ok": False, "error": {"type": "CorruptJournal", "message": message}}


# synthetic: am failing without an envelope at an exit code other than 3.
@pytest.mark.parametrize("text,exit_code", [
    ("boom\n", 1),
    ("Usage: am watch [OPTIONS] [RUN]\nError: Invalid value\n", 2),
], ids=["exit-1", "exit-2"])
def test_other_nonzero_without_envelope_is_bad_output(world, text, exit_code):
    set_raw(world, text, code=exit_code, stderr="error\n")
    code, out = run(world)
    assert code == 0
    assert out["ok"] is False
    assert out["error"]["type"] == "AmBadOutput"
    assert "am watch" in out["error"]["message"]
    assert "(exit %d)" % exit_code in out["error"]["message"]


# synthetic: am output at exit 0 that is not a usable envelope.
@pytest.mark.parametrize("text", [
    "not json\n",
    "",
    "[1, 2]\n",
    "null\n",
    '{"data": {"events": []}}\n',
    '{"ok": "true", "data": {"events": []}}\n',
    '{"ok": true}\n',
    '{"ok": true, "data": [1]}\n',
    '{"ok": true, "data": {}}\n',
    '{"ok": true, "data": {"events": {"seq": 1}}}\n',
    '{"ok": true, "data": {"events": [{"event": "run_upsert"}]}}\n',
    '{"ok": true, "data": {"events": [{"seq": "1"}]}}\n',
    '{"ok": true, "data": {"events": [{"seq": true}]}}\n',
    '{"ok": true, "data": {"events": [{"seq": 1.0}]}}\n',
    '{"ok": true, "data": {"events": [{"seq": 1}, 2]}}\n',
], ids=["not-json", "empty", "list", "null", "no-ok", "ok-string", "no-data",
        "data-list", "no-events", "events-object", "event-without-seq", "seq-string",
        "seq-bool", "seq-float", "event-not-object"])
def test_bad_output_at_exit_0(world, text):
    set_raw(world, text, code=0)
    code, out = run(world)
    assert code == 0
    assert out["ok"] is False
    assert out["error"]["type"] == "AmBadOutput"
    assert "am watch" in out["error"]["message"]
    assert "(exit 0)" in out["error"]["message"]


# --- am missing, catch-all ---------------------------------------------------------

def test_am_missing(world):
    empty = world["tmp"] / "empty-bin"
    empty.mkdir()
    code, out = run(world, PATH=str(empty))
    assert code == 0
    assert out == {"ok": False, "error": {"type": "AmMissing", "message": "am is not installed."}}


def test_am_cannot_start_is_helper_error(world):
    # Executable (so shutil.which finds it) but unstartable: subprocess raises
    # OSError and guarded() must still print exactly one JSON line.
    write_exec(world["bin"] / "am", "#!/nonexistent/interpreter\n")
    code, out = run(world)
    assert code == 0
    assert out["ok"] is False
    assert out["error"]["type"] == "HelperError"
    assert out["error"]["message"].startswith("The events snapshot failed: ")


def load_helper():
    """The script as a module (its name has a hyphen, so no plain import)."""
    spec = importlib.util.spec_from_file_location("runs_events", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_am_timeout_is_helper_error(world, monkeypatch, capsys):
    # An am that hangs is cut off after AM_TIMEOUT and reported as HelperError
    # (shortened here so the test does not wait the real 60 s).
    write_exec(world["bin"] / "am", "#!/usr/bin/env python3\nimport time\ntime.sleep(10)\n")
    helper = load_helper()
    assert helper.AM_TIMEOUT == 60
    monkeypatch.setattr(helper, "AM_TIMEOUT", 0.5)
    for key, value in env_for(world).items():
        monkeypatch.setenv(key, value)
    code = helper.guarded([RUN])
    lines = capsys.readouterr().out.splitlines()
    assert code == 0
    assert len(lines) == 1, lines
    out = json.loads(lines[0])
    assert out["ok"] is False
    assert out["error"]["type"] == "HelperError"
    assert out["error"]["message"].startswith("The events snapshot failed: ")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_events.py -q`
Expected: the Task 1 tests still PASS; `test_ok_wins_over_exit_code_and_stderr` also PASSES already (Task 1 ignores am's exit code; it is a pin for Review Focus 5); every other new test FAILS (33 failures) — e.g. `test_refusal_passthrough` with a `KeyError: 'data'` traceback and no stdout line, `test_bad_output_at_exit_0` with a `JSONDecodeError`/`KeyError` and no line, `test_am_missing` with a `TypeError` and no line, `test_am_timeout_is_helper_error` with `AttributeError: module 'runs_events' has no attribute 'guarded'`.

- [ ] **Step 3: Implement the error paths**

In `core/backend/runs/runs-events.py`, replace the module docstring (everything from the first `"""` through the closing `"""`) with:

```python
"""One run's events snapshot: a one-shot `am watch RUN` read.

    runs-events.py RUN [--since SEQ] [--tail N]

Runs `am watch RUN`, plus `--since SEQ` when given (SEQ verbatim), as an argv
list (no shell, stdin /dev/null, 60 s timeout); never `--follow`, `--repo-dir`,
`--all`, `--since-seq` or `--pretty`. am resolves RUN by id. `--tail` never
reaches am.

Prints exactly one JSON line on EVERY path:
- {"ok": true, "events": [...], "last_seq": N, "total": M} when am's envelope
  is `ok: true`; the envelope's `ok` decides, not am's exit code. `total` is
  the number of events am printed; `events` are those events in am's order,
  each unchanged, only the last N with `--tail N`; `last_seq` is the highest
  `seq` of every event am printed, or the `--since` value (0 without it) when
  there are none, so it can always be passed back as `--since`;
- am's {"ok": false, "error": ...} envelope, unchanged (UnknownRunError,
  StoreBusyError, ...), whatever am's exit code;
- {"ok": false, "error": {"type": "CorruptJournal", ...}} when am exits 3 and
  its stdout is not a JSON object with a boolean `ok`; the message is am's
  stderr, stripped, or "am watch exited 3.";
- {"ok": false, "error": {"type": "AmBadOutput", ...}} when am's stdout, at
  any other exit code, is not a JSON object with a boolean `ok`, or when an
  `ok: true` envelope has no object `data`, no list `data.events`, or an event
  that is not an object with an integer `seq`;
- {"ok": false, "error": {"type": "AmMissing", ...}} when am is not on PATH;
- {"ok": false, "error": {"type": "HelperError", ...}} on any unexpected
  failure (a timeout, an am that cannot start);
- {"ok": false, "error": {"type": "Usage", ...}} for any other argv: no RUN, an
  empty or `-`-prefixed RUN, a second positional, an unknown, repeated or
  valueless option, a SEQ that is not ASCII digits, an N that is not ASCII
  digits or is 0.
Exit 0 whenever a line was printed, refusals and errors included; exit 2 for
Usage only. Only the documented `am watch` command is used; am's database and
on-disk layout are never read.
"""
```

After the `OPTIONS = ("--since", "--tail")` line, add:

```python


class BadOutput(Exception):
    """am printed something that is not a usable envelope; the message says what."""
```

After `watch_argv`, add:

```python


def is_int(value):
    """True for a JSON integer (a bool is not one)."""
    return isinstance(value, int) and not isinstance(value, bool)


def envelope_of(stdout, returncode):
    """am's envelope, checked only for shape: a JSON object with a boolean `ok`."""
    exit_note = " (exit " + str(returncode) + ")."
    try:
        envelope = json.loads(stdout)
    except ValueError:
        raise BadOutput("am watch did not print JSON" + exit_note)
    if not isinstance(envelope, dict):
        raise BadOutput("am watch printed JSON that is not an object" + exit_note)
    if not isinstance(envelope.get("ok"), bool):
        raise BadOutput("am watch printed an object without a boolean ok field" + exit_note)
    return envelope


def events_of(envelope, returncode):
    """An ok envelope's `data.events`: a list of objects, each with an integer `seq`."""
    exit_note = " (exit " + str(returncode) + ")."
    data = envelope.get("data")
    if not isinstance(data, dict):
        raise BadOutput("am watch printed ok without a data object" + exit_note)
    events = data.get("events")
    if not isinstance(events, list):
        raise BadOutput("am watch printed data without an events list" + exit_note)
    if not all(isinstance(event, dict) and is_int(event.get("seq")) for event in events):
        raise BadOutput("am watch printed an event without an integer seq" + exit_note)
    return events
```

Replace the whole `main` function and the `if __name__ == "__main__":` block with:

```python
def main(argv):
    parsed = parse_args(argv)
    if parsed is None:
        return failure("Usage", USAGE, 2)
    run, since, tail = parsed
    am = shutil.which("am")
    if am is None:
        return failure("AmMissing", "am is not installed.")
    proc = subprocess.run([am, *watch_argv(run, since)], capture_output=True, text=True,
                          stdin=subprocess.DEVNULL, timeout=AM_TIMEOUT)
    try:
        envelope = envelope_of(proc.stdout, proc.returncode)
    except BadOutput as e:
        if proc.returncode == 3:
            return failure("CorruptJournal", proc.stderr.strip() or "am watch exited 3.")
        return failure("AmBadOutput", str(e))
    if not envelope["ok"]:
        return emit(envelope)
    try:
        events = events_of(envelope, proc.returncode)
    except BadOutput as e:
        return failure("AmBadOutput", str(e))
    return emit(snapshot(events, since, tail))


def guarded(argv):
    """The store parses stdout for exactly one JSON line, so no path - not even an
    unexpected exception (a timeout, an am that cannot start) - may end without one."""
    try:
        return main(argv)
    except SystemExit:
        raise
    except BaseException as e:  # noqa: BLE001 - deliberate catch-all
        reason = str(e) or e.__class__.__name__
        return failure("HelperError", "The events snapshot failed: " + reason)


if __name__ == "__main__":
    sys.exit(guarded(sys.argv[1:]))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_events.py -q`
Expected: all PASS (Task 1 and Task 2 tests).

- [ ] **Step 5: Add the architecture sentence**

In `docs/architecture.md` (line 196), replace this exact text:

```
`runs-logs.py <project_root> RUN CARD PHASE ATTEMPT` is a one-shot `am logs RUN CARD --phase P --attempt N --repo-dir R` passthrough: a 60 s timeout, exactly one JSON line. All three use only documented `am` commands,
```

with:

```
`runs-logs.py <project_root> RUN CARD PHASE ATTEMPT` is a one-shot `am logs RUN CARD --phase P --attempt N --repo-dir R` passthrough: a 60 s timeout, exactly one JSON line. `runs-events.py RUN [--since SEQ] [--tail N]` is a one-shot `am watch RUN [--since SEQ]` read (no `--follow`, no `--repo-dir`) that prints `{ok, events, last_seq, total}` -- `total` the matched count, `events` at most the last N with `--tail`, `last_seq` the highest `seq` of every matched event (the `--since` value, or 0, when none) -- or `{ok: false, error}`: am's refusal unchanged, `CorruptJournal` (am exit 3 without an envelope), `AmBadOutput`, `AmMissing`, `HelperError` (60 s timeout); `Usage` exits 2, every other path 0. All of them use only documented `am` commands,
```

Nothing else in the doc changes. Check: `git diff --stat docs/architecture.md` shows `1 file changed, 1 insertion(+), 1 deletion(-)`.

- [ ] **Step 6: Run the full suite**

Run: `bash tests/run.sh`
Expected: pytest all green (including `tests/architecture` and `tests/core/backend/runs/test_runs_events.py`), then every QML test with no `FAIL` line; exit status 0.

- [ ] **Step 7: Commit**

```bash
git add core/backend/runs/runs-events.py tests/core/backend/runs/test_runs_events.py docs/architecture.md
git commit -m "feat(runs-events): refusal passthrough, CorruptJournal, AmBadOutput, AmMissing and HelperError lines"
```
<!-- task-pipeline: validated -->
