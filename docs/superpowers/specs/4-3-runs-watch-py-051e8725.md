# 4.3 runs-watch.py: forwards a schema 1 or 2 hello (card 051e8725)

Narrowed from `docs/superpowers/specs/2026-10-05-align-run-model-design.md`
("the parent" below): Decision 8 (line 172), "Both spellings, both schemas"
(lines 286-289 and the `runs-watch.py` bullet at lines 296-300), the consumer
table row for `core/backend/runs/runs-watch.py:121-125` (line 129), the
`watch-hello.json` fixture row (line 248), the fixture rule (lines 257-267),
and "Not changed" (line 313: the backlog filter stays). Parent story 27d8a320,
work breakdown item 4 (parent lines 329-330).

This card is the `runs-watch.py` part of item 4 only. `runs.js` (card 4.1) and
`runs-snapshot.py` (card 4.2) are already on this branch; `RunStore.amSchema` /
`amVersion` (parent lines 301-302) and the Runs footer (parent lines 303-304)
are sibling cards that consume the line this card adds.

## Starting point

- `core/backend/runs/runs-watch.py`:
  - module docstring lines 7-14 list two output lines (`changed`, the error
    envelope); line 15 says "The hello line is dropped (its schema must be 1)".
  - `SchemaMismatch` docstring (line 46): "announced a journal schema other than 1".
  - `check_schema` (lines 121-125) raises unless `type(schema) is int and
    schema == 1`; message ends "this helper reads schema 1."
  - `stream()` (lines 185-187): every line with `event == "watch"` is passed to
    `check_schema` and then dropped. Its docstring names only `changed` lines,
    the refusal and `SchemaMismatch`.
  - `say()` emits one line and flushes it.
- `tests/fixtures/am/watch-hello.json`: `schema_1` (real, `am: "0.1.0"`) and
  `schema_2` (derived copy with `schema: 2`).
- `tests/core/backend/runs/test_runs_watch.py`: `hello(schema)` (lines 111-123)
  returns the `schema_1`/`schema_2` fixture lines, and a labelled synthetic
  `schema_1` copy for any other value (`MISSING` drops the key).
  `test_schema_mismatch` (line 369) is parametrized `[2, "1", MISSING]`.
  Most tests compare the whole output (`lines == [...]`, `len(lines)`,
  `changed(lines)`, which asserts every line is a `changed` line), and every
  script starts with `hello()`.
- `core/stores/RunStore.qml:239-250` `watchLine` ignores any line that is
  neither `changed` nor `ok: false`, so the new line is harmless to today's
  store.
- `tests/contract/test_am_shapes.py:159` already accepts `schema in (1, 2)`.

## Required behaviour

1. **Accepted schemas.** A hello line (a JSON object whose `event` is
   `"watch"`) is accepted when its `schema` is the integer `1` or `2`
   (`type(schema) is int`, so `true` is rejected). Anything else, including
   `3`, `0`, `"1"`, `"2"`, `2.0`, `true`, `null` or a missing key, ends the
   watch with `SchemaMismatch` exactly as today: one
   `{"ok": false, "error": {"type": "SchemaMismatch", "message": <non-empty>}}`
   line, exit 1, am terminated, and no `hello` line printed for that hello (a
   `hello` line already printed for an earlier accepted hello stays; rule 3).
   The message names the schema received (JSON-encoded) and the schemas read
   ("1 or 2").
2. **Forwarded once.** The first accepted hello is printed at once (flushed,
   not debounced) as exactly `{"hello": {"schema": N, "am": V}}` with `N` the
   announced integer and `V` the hello's `am` when it is a string, else `""`
   (missing, `null`, number, object). No other key of the hello (`runs_dir`,
   `event`, unknown keys) is forwarded.
3. **Later hellos.** Every hello line is still checked against rule 1 (a later
   hello with an unaccepted schema is `SchemaMismatch`, with any pending
   `changed` batch dropped as today). A later accepted hello prints nothing.
4. **Order.** The `hello` line precedes every `changed` line that follows it in
   am's stream; it does not flush or reset a pending batch.
5. **Journal lines unchanged under both schemas.** Backlog drop, the five
   events, the watched set, adoption by `run_upsert.payload.repo_dir`,
   debounce and dedupe behave identically after a schema 1 or a schema 2 hello
   (parent lines 298-300). No hello at all also behaves as today (journal lines
   still handled, nothing printed for a hello).
6. **Exit paths unchanged.** Usage, AmMissing, CorruptJournal, HelperError,
   refusal re-emission, SIGINT/SIGTERM and closed stdout keep their output and
   exit codes; the `hello` line, when printed, simply precedes their output.
7. **Docstrings state the contract only.** Module docstring: the output list
   gains `{"hello": {"schema": N, "am": "<version>"}}` (first accepted hello
   only; schema 1 or 2; am `""` when not a string), and the "hello line is
   dropped (its schema must be 1)" sentence is replaced; "the five schema-1
   events" becomes the five journal events. `SchemaMismatch`: "a journal schema
   other than 1 or 2". `stream()`: names the hello line. The `EVENTS` comment
   no longer says schema-1. No narrative about am's migration, cards or plans.

## Error paths

- Hello with `schema: 3` → `SchemaMismatch`, single line, am gone (rule 1).
- Hello with `schema: 2` but `am` missing or `5` → `{"hello": {"schema": 2,
  "am": ""}}` (rule 2).
- A refusal envelope with no hello → unchanged (no `hello` line).

## Tests (all in `tests/core/backend/runs/test_runs_watch.py`, pytest tier)

Pytest tier because `runs-watch.py` is a Python helper run as a subprocess
against the fake `am` that replays fixture lines; every existing test of it
lives here and runs in `bash tests/run.sh`. No QML or contract test observes
the helper's stdout. Inputs come from `watch-hello.json` / `watch-events.json`
via `json.load` through the existing `fixture`/`hello`/`ev`/`other` helpers;
any hand edit is on a fresh copy and labelled `synthetic:` (parent lines
257-267). No new fixture.

Helper changes:

- `HELLO1 = {"hello": {"schema": 1, "am": "0.1.0"}}` built from the fixture
  (`schema_1["schema"]`, `schema_1["am"]`), not hand-typed, and likewise
  `HELLO2`; a `split(lines)` helper (or equivalent) that asserts the first line
  is the expected hello and returns the rest, so existing `changed(lines)`
  assertions keep their meaning.
- `hello(schema, am=...)`: an option to drop or replace `am` on the copy,
  labelled `synthetic:` in the docstring.

Changed tests (expectations gain the leading hello line; nothing else moves):
`test_clean_exit_zero` (`lines == [HELLO1]`), `test_drops_hello_and_backlog`
(renamed `test_forwards_hello_and_drops_backlog`), `test_live_event_for_watched_run_emits_changed`,
`test_filters_unwatched_runs`, `test_ignores_unknown_events_and_keys`,
`test_missing_or_unparseable_ts_is_kept`, the three debounce tests, the
adoption test, `test_exit_3_corrupt_journal` and `test_other_exit_is_helper_error`
(three lines), `test_signal_stops_am_and_exits_zero` (first read line is
`HELLO1`, second is the `changed` line), `test_closed_stdout_exits_zero` (no
assertion change). Refusal tests have no hello and stay as they are.

`test_schema_mismatch`: parametrized `[3, "1", MISSING, True, 0]` with ids
`synthetic: three`, `string-one`, `missing`, `synthetic: true`,
`synthetic: zero`; `2` is removed. Same assertions (one line, SchemaMismatch,
non-empty message, under 5 s, am gone), plus the message contains the
received value's JSON (`3`, `"1"`, `null`, `true`, `0`).

New tests:

1. `test_hello_forwarded_for_schema` parametrized `schema in [1, 2]`: script
   `[hello(schema), ev()]` → `lines == [HELLO_N, {"changed": [WATCHED]}]`
   (rules 2, 4).
2. `test_hello_am_not_a_string` parametrized over `MISSING` and `5`
   (`synthetic:`): `hello(2, am=...)` → first line
   `{"hello": {"schema": 2, "am": ""}}` (rule 2).
3. `test_hello_forwarded_once`: `[hello(1), hello(2), hello(1), ev()]` →
   exactly one `hello` line, `HELLO1`, then `[[WATCHED]]` (rule 3).
4. `test_later_bad_hello_is_schema_mismatch`: `[hello(1), hello(3), ev(),
   pause(8)]` → `HELLO1` then the SchemaMismatch line only, under 5 s, am gone
   (rule 3).
5. `test_journal_same_under_both_schemas` parametrized `schema in [1, 2]`: the
   steps of the backlog/filter/adoption scenario (PAST lines, unwatched
   `other` lines, an adopted `run_upsert` with this root, a debounced burst)
   after `hello(schema)`; asserts the lines after the hello equal the same
   list for both schemas (rule 5).
6. `test_no_hello_still_streams`: `[ev()]` → `[{"changed": [WATCHED]}]`
   (rule 5).

Red first: tests 1-4 and the changed whole-output tests fail on today's code
(no `hello` line; schema 2 is a mismatch). The `test_schema_mismatch` cases
and test 6 already pass; they pin unchanged behaviour.

Verification: `bash tests/run.sh` green, including `tests/architecture` and
`tests/contract` (unaffected: no component, layering or icon change).

## Out of scope

- `RunStore.amSchema` / `amVersion` and reading the `hello` line in
  `watchLine`; the Runs footer text: sibling cards.
- `runs.js`, `runs-snapshot.py` (cards 4.1, 4.2, done).
- `--from-now`, the backlog filter, `EVENTS`, adoption, debounce timing
  (parent lines 177-180, 313).
- `tests/contract/test_am_shapes.py` (already accepts schema 1 or 2), fixtures.
- Docs (`docs/architecture.md`, README): work breakdown item 5.
