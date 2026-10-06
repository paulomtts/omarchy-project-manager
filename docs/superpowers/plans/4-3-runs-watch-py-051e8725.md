# 4.3 runs-watch.py: forwards a schema 1 or 2 hello: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `core/backend/runs/runs-watch.py` accepts an `am watch` hello line announcing journal schema 1 or 2 and prints the first accepted one as `{"hello": {"schema": N, "am": V}}`, leaving journal-line handling unchanged.

**Architecture:** `check_schema` accepts the integer 1 or 2 (a new `SCHEMAS` constant), returns the schema, and its `SchemaMismatch` message names "1 or 2". `stream()` keeps a `greeted` flag: the first accepted hello is printed at once through `say()` (flushed, outside the debounce batch, which it neither flushes nor resets); later accepted hellos print nothing; every hello is still checked. Docstrings and the `EVENTS` comment are rewritten to state the new contract.

**Tech Stack:** Python 3 (stdlib only), pytest, the helper run as a subprocess against a fake `am` that replays the captures in `tests/fixtures/am/`.

**Spec:** `docs/superpowers/specs/4-3-runs-watch-py-051e8725.md`. The full text is copied below.

## Spec (verbatim)

> # 4.3 runs-watch.py: forwards a schema 1 or 2 hello (card 051e8725)
>
> Narrowed from `docs/superpowers/specs/2026-10-05-align-run-model-design.md`
> ("the parent" below): Decision 8 (line 172), "Both spellings, both schemas"
> (lines 286-289 and the `runs-watch.py` bullet at lines 296-300), the consumer
> table row for `core/backend/runs/runs-watch.py:121-125` (line 129), the
> `watch-hello.json` fixture row (line 248), the fixture rule (lines 257-267),
> and "Not changed" (line 313: the backlog filter stays). Parent story 27d8a320,
> work breakdown item 4 (parent lines 329-330).
>
> This card is the `runs-watch.py` part of item 4 only. `runs.js` (card 4.1) and
> `runs-snapshot.py` (card 4.2) are already on this branch; `RunStore.amSchema` /
> `amVersion` (parent lines 301-302) and the Runs footer (parent lines 303-304)
> are sibling cards that consume the line this card adds.
>
> ## Starting point
>
> - `core/backend/runs/runs-watch.py`:
>   - module docstring lines 7-14 list two output lines (`changed`, the error
>     envelope); line 15 says "The hello line is dropped (its schema must be 1)".
>   - `SchemaMismatch` docstring (line 46): "announced a journal schema other than 1".
>   - `check_schema` (lines 121-125) raises unless `type(schema) is int and
>     schema == 1`; message ends "this helper reads schema 1."
>   - `stream()` (lines 185-187): every line with `event == "watch"` is passed to
>     `check_schema` and then dropped. Its docstring names only `changed` lines,
>     the refusal and `SchemaMismatch`.
>   - `say()` emits one line and flushes it.
> - `tests/fixtures/am/watch-hello.json`: `schema_1` (real, `am: "0.1.0"`) and
>   `schema_2` (derived copy with `schema: 2`).
> - `tests/core/backend/runs/test_runs_watch.py`: `hello(schema)` (lines 111-123)
>   returns the `schema_1`/`schema_2` fixture lines, and a labelled synthetic
>   `schema_1` copy for any other value (`MISSING` drops the key).
>   `test_schema_mismatch` (line 369) is parametrized `[2, "1", MISSING]`.
>   Most tests compare the whole output (`lines == [...]`, `len(lines)`,
>   `changed(lines)`, which asserts every line is a `changed` line), and every
>   script starts with `hello()`.
> - `core/stores/RunStore.qml:239-250` `watchLine` ignores any line that is
>   neither `changed` nor `ok: false`, so the new line is harmless to today's
>   store.
> - `tests/contract/test_am_shapes.py:159` already accepts `schema in (1, 2)`.
>
> ## Required behaviour
>
> 1. **Accepted schemas.** A hello line (a JSON object whose `event` is
>    `"watch"`) is accepted when its `schema` is the integer `1` or `2`
>    (`type(schema) is int`, so `true` is rejected). Anything else, including
>    `3`, `0`, `"1"`, `"2"`, `2.0`, `true`, `null` or a missing key, ends the
>    watch with `SchemaMismatch` exactly as today: one
>    `{"ok": false, "error": {"type": "SchemaMismatch", "message": <non-empty>}}`
>    line, exit 1, am terminated, and no `hello` line printed for that hello (a
>    `hello` line already printed for an earlier accepted hello stays; rule 3).
>    The message names the schema received (JSON-encoded) and the schemas read
>    ("1 or 2").
> 2. **Forwarded once.** The first accepted hello is printed at once (flushed,
>    not debounced) as exactly `{"hello": {"schema": N, "am": V}}` with `N` the
>    announced integer and `V` the hello's `am` when it is a string, else `""`
>    (missing, `null`, number, object). No other key of the hello (`runs_dir`,
>    `event`, unknown keys) is forwarded.
> 3. **Later hellos.** Every hello line is still checked against rule 1 (a later
>    hello with an unaccepted schema is `SchemaMismatch`, with any pending
>    `changed` batch dropped as today). A later accepted hello prints nothing.
> 4. **Order.** The `hello` line precedes every `changed` line that follows it in
>    am's stream; it does not flush or reset a pending batch.
> 5. **Journal lines unchanged under both schemas.** Backlog drop, the five
>    events, the watched set, adoption by `run_upsert.payload.repo_dir`,
>    debounce and dedupe behave identically after a schema 1 or a schema 2 hello
>    (parent lines 298-300). No hello at all also behaves as today (journal lines
>    still handled, nothing printed for a hello).
> 6. **Exit paths unchanged.** Usage, AmMissing, CorruptJournal, HelperError,
>    refusal re-emission, SIGINT/SIGTERM and closed stdout keep their output and
>    exit codes; the `hello` line, when printed, simply precedes their output.
> 7. **Docstrings state the contract only.** Module docstring: the output list
>    gains `{"hello": {"schema": N, "am": "<version>"}}` (first accepted hello
>    only; schema 1 or 2; am `""` when not a string), and the "hello line is
>    dropped (its schema must be 1)" sentence is replaced; "the five schema-1
>    events" becomes the five journal events. `SchemaMismatch`: "a journal schema
>    other than 1 or 2". `stream()`: names the hello line. The `EVENTS` comment
>    no longer says schema-1. No narrative about am's migration, cards or plans.
>
> ## Error paths
>
> - Hello with `schema: 3` → `SchemaMismatch`, single line, am gone (rule 1).
> - Hello with `schema: 2` but `am` missing or `5` → `{"hello": {"schema": 2,
>   "am": ""}}` (rule 2).
> - A refusal envelope with no hello → unchanged (no `hello` line).
>
> ## Tests (all in `tests/core/backend/runs/test_runs_watch.py`, pytest tier)
>
> Pytest tier because `runs-watch.py` is a Python helper run as a subprocess
> against the fake `am` that replays fixture lines; every existing test of it
> lives here and runs in `bash tests/run.sh`. No QML or contract test observes
> the helper's stdout. Inputs come from `watch-hello.json` / `watch-events.json`
> via `json.load` through the existing `fixture`/`hello`/`ev`/`other` helpers;
> any hand edit is on a fresh copy and labelled `synthetic:` (parent lines
> 257-267). No new fixture.
>
> Helper changes:
>
> - `HELLO1 = {"hello": {"schema": 1, "am": "0.1.0"}}` built from the fixture
>   (`schema_1["schema"]`, `schema_1["am"]`), not hand-typed, and likewise
>   `HELLO2`; a `split(lines)` helper (or equivalent) that asserts the first line
>   is the expected hello and returns the rest, so existing `changed(lines)`
>   assertions keep their meaning.
> - `hello(schema, am=...)`: an option to drop or replace `am` on the copy,
>   labelled `synthetic:` in the docstring.
>
> Changed tests (expectations gain the leading hello line; nothing else moves):
> `test_clean_exit_zero` (`lines == [HELLO1]`), `test_drops_hello_and_backlog`
> (renamed `test_forwards_hello_and_drops_backlog`), `test_live_event_for_watched_run_emits_changed`,
> `test_filters_unwatched_runs`, `test_ignores_unknown_events_and_keys`,
> `test_missing_or_unparseable_ts_is_kept`, the three debounce tests, the
> adoption test, `test_exit_3_corrupt_journal` and `test_other_exit_is_helper_error`
> (three lines), `test_signal_stops_am_and_exits_zero` (first read line is
> `HELLO1`, second is the `changed` line), `test_closed_stdout_exits_zero` (no
> assertion change). Refusal tests have no hello and stay as they are.
>
> `test_schema_mismatch`: parametrized `[3, "1", MISSING, True, 0]` with ids
> `synthetic: three`, `string-one`, `missing`, `synthetic: true`,
> `synthetic: zero`; `2` is removed. Same assertions (one line, SchemaMismatch,
> non-empty message, under 5 s, am gone), plus the message contains the
> received value's JSON (`3`, `"1"`, `null`, `true`, `0`).
>
> New tests:
>
> 1. `test_hello_forwarded_for_schema` parametrized `schema in [1, 2]`: script
>    `[hello(schema), ev()]` → `lines == [HELLO_N, {"changed": [WATCHED]}]`
>    (rules 2, 4).
> 2. `test_hello_am_not_a_string` parametrized over `MISSING` and `5`
>    (`synthetic:`): `hello(2, am=...)` → first line
>    `{"hello": {"schema": 2, "am": ""}}` (rule 2).
> 3. `test_hello_forwarded_once`: `[hello(1), hello(2), hello(1), ev()]` →
>    exactly one `hello` line, `HELLO1`, then `[[WATCHED]]` (rule 3).
> 4. `test_later_bad_hello_is_schema_mismatch`: `[hello(1), hello(3), ev(),
>    pause(8)]` → `HELLO1` then the SchemaMismatch line only, under 5 s, am gone
>    (rule 3).
> 5. `test_journal_same_under_both_schemas` parametrized `schema in [1, 2]`: the
>    steps of the backlog/filter/adoption scenario (PAST lines, unwatched
>    `other` lines, an adopted `run_upsert` with this root, a debounced burst)
>    after `hello(schema)`; asserts the lines after the hello equal the same
>    list for both schemas (rule 5).
> 6. `test_no_hello_still_streams`: `[ev()]` → `[{"changed": [WATCHED]}]`
>    (rule 5).
>
> Red first: tests 1-4 and the changed whole-output tests fail on today's code
> (no `hello` line; schema 2 is a mismatch). The `test_schema_mismatch` cases
> and test 6 already pass; they pin unchanged behaviour.
>
> Verification: `bash tests/run.sh` green, including `tests/architecture` and
> `tests/contract` (unaffected: no component, layering or icon change).
>
> ## Out of scope
>
> - `RunStore.amSchema` / `amVersion` and reading the `hello` line in
>   `watchLine`; the Runs footer text: sibling cards.
> - `runs.js`, `runs-snapshot.py` (cards 4.1, 4.2, done).
> - `--from-now`, the backlog filter, `EVENTS`, adoption, debounce timing
>   (parent lines 177-180, 313).
> - `tests/contract/test_am_shapes.py` (already accepts schema 1 or 2), fixtures.
> - Docs (`docs/architecture.md`, README): work breakdown item 5.

## Global Constraints

- Accepted hello schemas: exactly the integers `1` and `2` (`type(schema) is int`); `true`, `2.0`, `"1"`, `"2"`, `0`, `3`, `null`, missing → `SchemaMismatch`.
- `SchemaMismatch` output is exactly one `{"ok": false, "error": {"type": "SchemaMismatch", "message": <non-empty>}}` line, exit 1, am terminated; the message names the received schema JSON-encoded and "1 or 2".
- The hello output line is exactly `{"hello": {"schema": N, "am": V}}`; `V` is the hello's `am` when a string, else `""`; no other hello key is forwarded.
- Only the first accepted hello is printed, at once (flushed via `say()`), never debounced; it does not flush or reset a pending `changed` batch.
- Backlog drop, `EVENTS`, watched set, adoption, debounce (`WINDOW = 0.25`), dedupe, `--follow` argv, exit codes and every other output line unchanged.
- Docstrings/comments state the contract only: no narrative about am's migration, cards or plans.
- No new fixture; every hand-edited line is a fresh copy labelled `synthetic:`.
- All tests go in `tests/core/backend/runs/test_runs_watch.py` (pytest tier).
- Verification: `bash tests/run.sh` green, `tests/architecture` and `tests/contract` included.
- Not edited: `core/stores/RunStore.qml`, `core/domain/runs.js`, `runs-snapshot.py`, fixtures, `tests/contract/*`, docs.

## Review Focus

1. A hello whose `am` is `null` or an object (not only missing or a number) must still forward `"am": ""`, never `null` or the object. Pinned in Task 1 by adding `None` and `{"v": 1}` cases to `test_hello_am_not_a_string`.
2. A hello carrying an unknown key (a newer am adding fields) must not leak it into the output line. Pinned in Task 1 by `test_hello_unknown_keys_not_forwarded`.
3. A float `2.0` or a string `"2"` schema must be a mismatch (a sloppy `in (1, 2)` or `int()` would accept them). Pinned in Task 1 by adding `2.0` and `"2"` cases to `test_schema_mismatch`.
4. A hello arriving while a `changed` batch is pending must print at once without flushing or clearing that batch (the run ids before and after it land in one `changed` line). Pinned in Task 1 by `test_hello_mid_batch_keeps_the_batch`.
5. An accepted hello followed by an am refusal envelope (exit 0) must print the hello, then the envelope unchanged, exit 1; and a later bad hello with a batch pending must drop the batch. Pinned in Task 1 by `test_refusal_after_hello_is_reemitted` and the `pending-batch` case of `test_later_bad_hello_is_schema_mismatch`.

---

## How to run the tests

`python3` on this machine has no pytest; use uv's throwaway environment:

- One file: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_watch.py -q`
- One test: append `::test_name` (or `-k name`).
- Everything: `bash tests/run.sh` (pytest then every QML test; it falls back to `uv` by itself).

Baseline before this plan: `25 passed` for `test_runs_watch.py`.

## File Structure

- Modify `core/backend/runs/runs-watch.py`: module docstring (lines 6-18), `EVENTS` comment (line 41) plus a new `SCHEMAS` constant, `SchemaMismatch` docstring (line 47), `check_schema` (lines 121-125), `stream()` (lines 157-191).
- Modify `tests/core/backend/runs/test_runs_watch.py`: helpers (`hello`, new `KEEP`, `HELLO1`, `HELLO2`, `split`), `test_lines_are_capture_copies`, every whole-output test listed in the spec, `test_schema_mismatch`, plus the new tests.

One task: the helper change and its test changes cannot be separated (forwarding the hello changes every whole-output test's expectation).

---

### Task 1: Accept a schema 1 or 2 hello and forward the first one

**Files:**
- Modify: `core/backend/runs/runs-watch.py:6-18, 41-47, 121-125, 157-191`
- Test: `tests/core/backend/runs/test_runs_watch.py`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces (for the sibling `RunStore` card): one stdout line `{"hello": {"schema": <1|2>, "am": <string>}}`, printed before any `changed` line that follows the hello in am's stream, at most once per helper run. In `runs-watch.py`: `SCHEMAS = (1, 2)`; `check_schema(hello: dict) -> int` (returns the accepted schema, raises `SchemaMismatch`).

- [ ] **Step 1: Update the test helpers**

In `tests/core/backend/runs/test_runs_watch.py`, replace lines 74-75:

```python
# The run of every captured journal line.
WATCHED = fixture("watch-events.json")["data"]["events"][0]["run_id"]
```

with:

```python
# The run of every captured journal line.
WATCHED = fixture("watch-events.json")["data"]["events"][0]["run_id"]


def hello_line(schema):
    """The helper's hello output line for the capture's schema_<schema> hello."""
    line = fixture("watch-hello.json")["schema_%d" % schema]
    return {"hello": {"schema": line["schema"], "am": line["am"]}}


HELLO1 = hello_line(1)
HELLO2 = hello_line(2)
```

Replace the whole `hello` function (lines 111-123):

```python
def hello(schema=1):
    """The --follow hello: the captured schema_1 line, or the capture's derived
    schema_2 line for schema=2. synthetic: any other schema value is set on a
    schema_1 copy; MISSING leaves the key out."""
    lines = fixture("watch-hello.json")
    if type(schema) is int and schema in (1, 2):
        return {"line": lines["schema_%d" % schema]}
    line = lines["schema_1"]
    if schema is MISSING:
        del line["schema"]
    else:
        line["schema"] = schema
    return {"line": line}
```

with:

```python
KEEP = object()


def hello(schema=1, am=KEEP):
    """The --follow hello: the captured schema_1 line, or the capture's derived
    schema_2 line for schema=2. synthetic: any other schema value is set on a
    schema_1 copy; MISSING leaves the key out. synthetic: am, unless KEEP, is set
    to the given value on the copy; MISSING leaves the key out."""
    lines = fixture("watch-hello.json")
    if type(schema) is int and schema in (1, 2):
        line = lines["schema_%d" % schema]
    else:
        line = lines["schema_1"]
        if schema is MISSING:
            del line["schema"]
        else:
            line["schema"] = schema
    if am is MISSING:
        del line["am"]
    elif am is not KEEP:
        line["am"] = am
    return {"line": line}
```

Right after the `changed` function (after line 198, before `def calls(world):`), add with two blank lines on each side:

```python
def split(lines, greeting=HELLO1):
    """The lines after the leading hello line, which must be `greeting`."""
    assert lines, lines
    assert lines[0] == greeting, lines
    return lines[1:]
```

In `test_lines_are_capture_copies`, after the last line `assert hello(2) == {"line": fixture("watch-hello.json")["schema_2"]}`, add:

```python
    assert HELLO1 == {"hello": {"schema": 1, "am": "0.1.0"}}
    assert HELLO2 == {"hello": {"schema": 2, "am": "0.1.0"}}
```

- [ ] **Step 2: Update the whole-output tests**

`test_clean_exit_zero`: replace `    assert lines == []` with:

```python
    assert lines == [HELLO1]
```

Replace the whole `test_drops_hello_and_backlog` with:

```python
def test_forwards_hello_and_drops_backlog(world):
    # WATCHED's lines were written an hour before the helper started: backlog,
    # dropped. r2's line is live and proves the helper is reading at all.
    set_script(world, [hello(), ev(ts="PAST"), ev("subtask_upsert", ts="PAST"),
                       other("r2")])
    code, lines, _ = run_helper(world, [str(world["proj"]), WATCHED, "r2"])
    assert code == 0
    assert changed(split(lines)) == [["r2"]]
```

`test_live_event_for_watched_run_emits_changed`: replace `    assert lines == [{"changed": [WATCHED]}]` with:

```python
    assert lines == [HELLO1, {"changed": [WATCHED]}]
```

`test_filters_unwatched_runs`: replace `    assert changed(lines) == [[WATCHED]]` with:

```python
    assert changed(split(lines)) == [[WATCHED]]
```

`test_ignores_unknown_events_and_keys`: replace `    assert changed(lines) == [[WATCHED]]` with:

```python
    assert changed(split(lines)) == [[WATCHED]]
```

`test_missing_or_unparseable_ts_is_kept`: replace `    assert changed(lines) == [sorted([WATCHED, "r2"])]` with:

```python
    assert changed(split(lines)) == [sorted([WATCHED, "r2"])]
```

`test_debounce_batches_and_dedupes`: replace `    assert changed(lines) == [sorted([WATCHED, "r2"])]` with:

```python
    assert changed(split(lines)) == [sorted([WATCHED, "r2"])]
```

`test_debounce_separate_windows`: replace `    assert changed(lines) == [[WATCHED], [WATCHED]]` with:

```python
    assert changed(split(lines)) == [[WATCHED], [WATCHED]]
```

`test_debounce_continuous_stream_is_rate_limited`: replace `    got = changed(lines)` with:

```python
    got = changed(split(lines))
```

`test_new_run_upsert_in_project_is_adopted`: replace `    assert changed(lines) == [["n1"], ["n1"]]` with:

```python
    assert changed(split(lines)) == [["n1"], ["n1"]]
```

`test_exit_3_corrupt_journal`: replace its last five lines

```python
    assert len(lines) == 2, lines
    assert lines[0] == {"changed": [WATCHED]}  # the pending batch is flushed first
    assert lines[1]["ok"] is False
    assert lines[1]["error"]["type"] == "CorruptJournal"
    assert "journal line 4 of run r1 is not JSON" in lines[1]["error"]["message"]
```

with:

```python
    assert len(lines) == 3, lines
    assert lines[0] == HELLO1
    assert lines[1] == {"changed": [WATCHED]}  # the pending batch is flushed first
    assert lines[2]["ok"] is False
    assert lines[2]["error"]["type"] == "CorruptJournal"
    assert "journal line 4 of run r1 is not JSON" in lines[2]["error"]["message"]
```

`test_other_exit_is_helper_error`: replace its last five lines

```python
    assert len(lines) == 2, lines
    assert lines[0] == {"changed": [WATCHED]}
    assert lines[1]["ok"] is False
    assert lines[1]["error"]["type"] == "HelperError"
    assert "boom" in lines[1]["error"]["message"]
```

with:

```python
    assert len(lines) == 3, lines
    assert lines[0] == HELLO1
    assert lines[1] == {"changed": [WATCHED]}
    assert lines[2]["ok"] is False
    assert lines[2]["error"]["type"] == "HelperError"
    assert "boom" in lines[2]["error"]["message"]
```

`test_signal_stops_am_and_exits_zero`: replace

```python
        first = p.stdout.readline()  # sync point: am is running, helper is streaming
        assert json.loads(first) == {"changed": [WATCHED]}
```

with:

```python
        assert json.loads(p.stdout.readline()) == HELLO1
        second = p.stdout.readline()  # sync point: am is running, helper is streaming
        assert json.loads(second) == {"changed": [WATCHED]}
```

`test_closed_stdout_exits_zero`, `test_usage`, `test_am_missing` and both refusal tests: no change.

- [ ] **Step 3: Replace `test_schema_mismatch`**

Replace the whole test (decorator included) with:

```python
@pytest.mark.parametrize("schema", [3, "1", MISSING, True, 0, 2.0, "2"],
                         ids=["synthetic: three", "string-one", "missing", "synthetic: true",
                              "synthetic: zero", "synthetic: two-float", "synthetic: string-two"])
def test_schema_mismatch(world, schema):
    # am would keep streaming for 8 s; the helper must stop it and leave at once.
    set_script(world, [hello(schema), ev(), pause(8)])
    began = time.monotonic()
    code, lines, _ = run_helper(world)
    assert time.monotonic() - began < 5
    assert code != 0
    assert len(lines) == 1, lines
    assert lines[0]["ok"] is False
    assert lines[0]["error"]["type"] == "SchemaMismatch"
    message = lines[0]["error"]["message"]
    assert message
    received = json.dumps(None if schema is MISSING else schema)
    assert "schema " + received in message, message
    assert "1 or 2" in message, message
    assert_gone(am_pid(world))  # am was terminated, not left streaming
```

- [ ] **Step 4: Add the new tests**

Insert this block right after `test_new_run_upsert_in_project_is_adopted` and before the `# --- error paths ---` comment, with two blank lines on each side:

```python
# --- the hello line ---------------------------------------------------------------

@pytest.mark.parametrize("schema, greeting", [(1, HELLO1), (2, HELLO2)], ids=["one", "two"])
def test_hello_forwarded_for_schema(world, schema, greeting):
    # Only schema and am are forwarded (not event or runs_dir), before the
    # changed line that follows the hello.
    set_script(world, [hello(schema), ev()])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == [greeting, {"changed": [WATCHED]}]


# synthetic: hellos whose am is missing, a number, null or an object.
@pytest.mark.parametrize("am", [MISSING, 5, None, {"v": 1}],
                         ids=["synthetic: missing", "synthetic: number", "synthetic: null",
                              "synthetic: object"])
def test_hello_am_not_a_string(world, am):
    set_script(world, [hello(2, am=am), ev()])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == [{"hello": {"schema": 2, "am": ""}}, {"changed": [WATCHED]}]


def test_hello_unknown_keys_not_forwarded(world):
    step = hello(2)
    step["line"]["shiny"] = {"new": 1}  # synthetic: a hello key no capture has
    set_script(world, [step, ev()])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == [HELLO2, {"changed": [WATCHED]}]


def test_hello_forwarded_once(world):
    set_script(world, [hello(1), hello(2), hello(1), ev()])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert [line for line in lines if "hello" in line] == [HELLO1]
    assert changed(split(lines)) == [[WATCHED]]


def test_hello_mid_batch_keeps_the_batch(world):
    # WATCHED's line opens a batch; the hello is printed at once without
    # flushing or clearing it, so r2 joins the same changed line.
    set_script(world, [ev(), hello(1), other("r2"), pause(0.6)])
    code, lines, _ = run_helper(world, [str(world["proj"]), WATCHED, "r2"])
    assert code == 0
    assert changed(split(lines)) == [sorted([WATCHED, "r2"])]


@pytest.mark.parametrize("steps", [
    [hello(1), hello(3), ev(), pause(8)],
    [hello(1), ev(), hello(3), ev(), pause(8)],  # the pending batch is dropped
], ids=["synthetic: three", "synthetic: three, pending-batch"])
def test_later_bad_hello_is_schema_mismatch(world, steps):
    set_script(world, steps)
    began = time.monotonic()
    code, lines, _ = run_helper(world)
    assert time.monotonic() - began < 5
    assert code != 0
    assert len(lines) == 2, lines
    assert lines[0] == HELLO1
    assert lines[1]["ok"] is False
    assert lines[1]["error"]["type"] == "SchemaMismatch"
    assert lines[1]["error"]["message"]
    assert_gone(am_pid(world))


@pytest.mark.parametrize("schema, greeting", [(1, HELLO1), (2, HELLO2)], ids=["one", "two"])
def test_journal_same_under_both_schemas(world, schema, greeting):
    root = str(world["proj"])
    set_script(world, [
        hello(schema),
        ev(ts="PAST"),                                          # backlog: dropped
        other("r9"),                                            # unwatched: dropped
        other("r7", "run_upsert", repo_dir="/somewhere/else"),  # other repo: ignored
        other("n1", "run_upsert", repo_dir=root),               # this project: adopted
        ev(), other("n1"), ev("subtask_upsert"),                # one debounced burst
        pause(0.6),
        other("n1"),                                            # adopted: kept from now on
        pause(0.6),
    ])
    code, lines, _ = run_helper(world, [root, WATCHED])
    assert code == 0
    assert changed(split(lines, greeting)) == [sorted([WATCHED, "n1"]), ["n1"]]


def test_no_hello_still_streams(world):
    set_script(world, [ev()])
    code, lines, _ = run_helper(world)
    assert code == 0
    assert lines == [{"changed": [WATCHED]}]
```

Then, right after `test_refusal_other_exit_is_reemitted` (before the `# --- stopping: ...` comment), add with two blank lines on each side:

```python
def test_refusal_after_hello_is_reemitted(world):
    # synthetic: an am refusal envelope; no capture holds one.
    envelope = {"error": {"message": "something else", "type": "OddError"}, "ok": False}
    set_script(world, [hello(2), {"line": envelope}], exit=0)
    code, lines, _ = run_helper(world)
    assert code != 0
    assert lines == [HELLO2, envelope]
```

Note: `test_later_bad_hello_is_schema_mismatch`'s parametrize list calls `hello()`/`ev()` at import time; that is fine (they only read fixtures, and each call returns a fresh copy).

- [ ] **Step 5: Run the tests to verify the right ones fail**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_watch.py -q`

Expected: 44 collected, `37 failed, 7 passed`.

Must pass already (they pin unchanged behaviour): `test_lines_are_capture_copies`, `test_usage`, `test_am_missing`, `test_refusal_exit_3_is_corrupt_journal`, `test_refusal_other_exit_is_reemitted`, `test_closed_stdout_exits_zero`, `test_no_hello_still_streams`. If any of these fails, stop: the test is wrong, not the code.

Must fail: every changed whole-output test (no `hello` line yet: `AssertionError` from `split` or the list compare), all 7 `test_schema_mismatch` cases (`AssertionError` on `"1 or 2" in message`: today's message says "reads schema 1."), and every other new test (no hello line, or schema 2 refused as `SchemaMismatch`).

- [ ] **Step 6: Accept schema 1 or 2 in `check_schema`**

In `core/backend/runs/runs-watch.py`, replace lines 41-43:

```python
# The schema-1 journal events. Any other `event` value is ignored.
EVENTS = frozenset({"run_upsert", "story_upsert", "subtask_upsert", "phase_upsert",
                    "attempt_upsert"})
```

with:

```python
# The journal events. Any other `event` value is ignored.
EVENTS = frozenset({"run_upsert", "story_upsert", "subtask_upsert", "phase_upsert",
                    "attempt_upsert"})
# The journal schemas a hello line may announce, as JSON integers.
SCHEMAS = (1, 2)
```

Replace line 47:

```python
    """The hello line announced a journal schema other than 1."""
```

with:

```python
    """The hello line announced a journal schema other than 1 or 2."""
```

Replace `check_schema` (lines 121-125):

```python
def check_schema(hello):
    schema = hello.get("schema")
    if not (type(schema) is int and schema == 1):
        raise SchemaMismatch("am watch speaks journal schema " + json.dumps(schema)
                             + "; this helper reads schema 1.")
```

with:

```python
def check_schema(hello):
    """The hello line's journal schema, an integer in SCHEMAS. Raises SchemaMismatch."""
    schema = hello.get("schema")
    if not (type(schema) is int and schema in SCHEMAS):
        raise SchemaMismatch("am watch speaks journal schema " + json.dumps(schema)
                             + "; this helper reads schema 1 or 2.")
    return schema
```

(`type(schema) is int` rejects `True` and `2.0`; `json.dumps` of a missing key's `None` is `null`.)

- [ ] **Step 7: Forward the first accepted hello in `stream()`**

Replace the docstring and first line of `stream()`:

```python
    """Turn am's stream into debounced {"changed": [...]} lines until it ends.
    Trailing edge: the first kept run id into an empty batch opens a WINDOW;
    when it closes the batch is printed once and cleared. A pending batch is
    printed when the stream ends. Returns am's refusal envelope (the only line
    with an "ok" key) if it printed one, else None. Raises SchemaMismatch."""
    batch, deadline, refusal = [], None, None
```

with:

```python
    """Turn am's stream into the hello line and debounced {"changed": [...]}
    lines until it ends. Every hello line (event "watch") is checked; the first
    is printed at once as {"hello": {"schema", "am"}}, am "" when not a string,
    without touching the batch; later ones print nothing. Trailing edge: the
    first kept run id into an empty batch opens a WINDOW; when it closes the
    batch is printed once and cleared. A pending batch is printed when the
    stream ends. Returns am's refusal envelope (the only line with an "ok" key)
    if it printed one, else None. Raises SchemaMismatch."""
    batch, deadline, refusal, greeted = [], None, None, False
```

Replace:

```python
        if isinstance(line, dict) and line.get("event") == "watch":
            check_schema(line)
            continue
```

with:

```python
        if isinstance(line, dict) and line.get("event") == "watch":
            schema = check_schema(line)
            if not greeted:
                version = line.get("am")
                say({"hello": {"schema": schema,
                               "am": version if isinstance(version, str) else ""}})
                greeted = True
            continue
```

- [ ] **Step 8: Rewrite the module docstring**

Replace lines 6-21 of the module docstring:

```
Long-lived. Spawns `am watch --all --follow` (an argv list, never a shell) and
prints one JSON line per output event, flushed at once:
  {"changed": ["<run id>", ...]}  at most once per 250 ms, never empty, run ids
                                  only (event contents are never forwarded)
  {"ok": false, "error": {"type", "message"}}  then exit 1, with type
                                  SchemaMismatch, CorruptJournal, HelperError or
                                  AmMissing (Usage exits 2); an am refusal
                                  envelope with an exit other than 3 is
                                  re-emitted unchanged.
The hello line is dropped (its schema must be 1). Journal lines written before
the helper started (the backlog) are dropped. A journal line is kept when its
event is one of the five schema-1 events and its run id is watched: the argv run
ids, plus every run whose run_upsert payload.repo_dir is this project root.
Unknown events, unknown keys and non-JSON lines are ignored. am exiting 0,
SIGINT, SIGTERM or a closed stdout end the helper with exit 0. Only the `am`
command is used; am's database and on-disk layout are never read.
```

with:

```
Long-lived. Spawns `am watch --all --follow` (an argv list, never a shell) and
prints one JSON line per output event, flushed at once:
  {"hello": {"schema": N, "am": "<version>"}}  for the first accepted hello
                                  line only: N is its journal schema, 1 or 2;
                                  am is its am version, "" when not a string
  {"changed": ["<run id>", ...]}  at most once per 250 ms, never empty, run ids
                                  only (event contents are never forwarded)
  {"ok": false, "error": {"type", "message"}}  then exit 1, with type
                                  SchemaMismatch, CorruptJournal, HelperError or
                                  AmMissing (Usage exits 2); an am refusal
                                  envelope with an exit other than 3 is
                                  re-emitted unchanged.
Every hello line (event "watch") must announce journal schema 1 or 2, else
SchemaMismatch; none of its other keys is forwarded. Journal lines are handled
the same under either schema. Journal lines written before the helper started
(the backlog) are dropped. A journal line is kept when its event is one of the
five journal events and its run id is watched: the argv run ids, plus every run
whose run_upsert payload.repo_dir is this project root. Unknown events, unknown
keys and non-JSON lines are ignored. am exiting 0, SIGINT, SIGTERM or a closed
stdout end the helper with exit 0. Only the `am` command is used; am's database
and on-disk layout are never read.
```

Do not touch `keep`, `is_backlog`, `spawn`, `finish`, `main` or anything else.

- [ ] **Step 9: Run the file to verify everything passes**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_watch.py -q`
Expected: `44 passed`.

Also confirm no stale wording remains:

Run: `grep -n "schema-1\|schema must be 1\|reads schema 1\.\|other than 1\.\|dropped (its" core/backend/runs/runs-watch.py`
Expected: no output.

- [ ] **Step 10: Run the full suite**

Run: `bash tests/run.sh; echo "exit=$?"`
Expected: pytest all passed (including `tests/architecture` and `tests/contract`), every QML file `Totals: N passed, 0 failed`, and `exit=0`.

- [ ] **Step 11: Commit**

```bash
git add core/backend/runs/runs-watch.py tests/core/backend/runs/test_runs_watch.py
git commit -m "feat(runs): runs-watch forwards a schema 1 or 2 hello"
```

---

## Self-review against the spec

- Rule 1 (accepted schemas, mismatch output, message names value and "1 or 2"): Steps 3, 6; `test_later_bad_hello_is_schema_mismatch` (Step 4) pins the earlier hello line staying.
- Rule 2 (forwarded once, exact shape, `am` fallback, no other keys): Steps 4 (`test_hello_forwarded_for_schema`, `test_hello_am_not_a_string`, `test_hello_unknown_keys_not_forwarded`), 7.
- Rule 3 (later hellos checked; later accepted prints nothing; pending batch dropped): Step 4 (`test_hello_forwarded_once`, `test_later_bad_hello_is_schema_mismatch` both cases), 7.
- Rule 4 (order; no flush/reset): Step 4 (`test_hello_forwarded_for_schema`, `test_hello_mid_batch_keeps_the_batch`), 7.
- Rule 5 (journal unchanged under both schemas; no hello): Step 4 (`test_journal_same_under_both_schemas`, `test_no_hello_still_streams`); Step 2 keeps every journal test.
- Rule 6 (exit paths unchanged, hello precedes): Step 2 (exit 3, other exit, signals, closed stdout), Step 4 (`test_refusal_after_hello_is_reemitted`); refusal-without-hello tests unchanged.
- Rule 7 (docstrings/comments): Steps 6, 7, 8; stale-wording grep in Step 9.
- Spec helper changes (`HELLO1`/`HELLO2` from fixture, `split`, `hello(schema, am=...)` labelled synthetic): Step 1.
- Spec changed tests and renamed test: Step 2. `test_schema_mismatch` ids/values from the spec plus Review Focus 3 extras: Step 3. New tests 1-6: Step 4. Red first: Step 5 (deviation: the `test_schema_mismatch` cases also fail red, because the plan adds the spec-required `"1 or 2"` message assertion). Verification: Step 10.
- Out of scope untouched: Global Constraints last line.
<!-- task-pipeline: validated -->
