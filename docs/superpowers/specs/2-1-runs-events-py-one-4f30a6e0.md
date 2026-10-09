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
