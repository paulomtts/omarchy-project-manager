# 1.5 viewer-state.py: prefixByMilestone — design

Card: `02ca6d9d` (subtask of story `5c0430d9`). Parent design:
`docs/superpowers/specs/2026-10-05-dispatch-story-level-design.md` (S7), cited below as
"S7 l.N".

## Purpose

The default branch prefix for a story or milestone dispatch comes from, in order: the newest
run of the milestone, then "the last prefix used for that milestone through the panel (the
per-project run settings, keyed by milestone id)", then S3's prefix history, then the
milestone's stem (S7 l.49-54). `core/domain/runs.js` already reads the second source as
`settings.prefixByMilestone` (card 1.3, `core/domain/runs.js:987-1002`). Nothing stores it
yet. This card adds `prefixByMilestone` to the per-project run settings in
`core/backend/projects/viewer-state.py`: it is read by `get-run-settings`, written by
`set-run-settings` and validated like the other fields.

## Inherited constraints

- Run settings gain "a `prefixByMilestone` map next to the existing prefix history,
  validated like the other fields; S3's history stays for the fallback" (S7 l.85-86).
  `prefixHistory` keeps its behaviour, its cap and its sentence byte for byte.
- The map is keyed by milestone id (S7 l.52-53). The keys are milestone card ids, never
  story or subtask ids. The caller (card 2.1) chooses the key. This helper stores what it is
  given.
- Backend pytest covers the `prefixByMilestone` round trip (S7 l.99-101).
- Card: the value is a map from milestone card id to a non-empty prefix string. These are
  refused with a sentence before anything is written: a non-object, empty keys, and values
  that are not strings or are empty. The map is merged per milestone key, so setting one
  milestone keeps the others. The default is `{}`. Update the module docstring and the usage
  text.
- Card: tests go in `tests/core/backend/projects/test_viewer_state.py` and cover get default,
  set/get round trip, merge, refusals, and an atomic write that keeps other keys.
- Layering per `docs/architecture.md`: `tests/architecture` must pass. A Python-only change
  to one backend helper adds no component or glyph. Verification is `bash tests/run.sh`
  green. TDD: tests first. Docstrings and comments state the contract only, with no
  narrative (card).

## Behaviour

### The field

- Name: `prefixByMilestone`. Default: `{}`.
- Valid value: a JSON object in which every key is a string with a non-whitespace
  character and every value is a string with a non-whitespace character. This is the same
  `.strip()` test `verify` and `prefixHistory` use for their elements
  (`viewer-state.py:72-77`). An empty object is valid.
- The map has no size cap. Keys and values are stored and returned verbatim, including
  surrounding whitespace and non-ASCII text, as `prefixHistory` strings are. Trimming is the
  reader's job (`runs.js` trims every value it takes).

### `get-run-settings ROOT`

- The reply always carries `prefixByMilestone`, with seven keys in total. With no file, no
  entry for ROOT, or a damaged file, the value is `{}`.
- A stored valid map is returned as stored.
- A stored value that is not valid as a whole is returned as `{}`. That covers a non-object,
  one blank key, and one value that is not a string or is blank. The other six fields are
  unaffected, since each field falls back on its own, as today. One bad entry voids the whole
  map, just as one bad element voids a stored `verify` or `prefixHistory` list.
- `get-run-settings` still never writes and never fails, and its output stays strict JSON.

### `set-run-settings ROOT JSON`

- `prefixByMilestone` is accepted alongside any other known keys, and the update stays
  partial. A key not given is left untouched in the stored entry, and that includes a stored
  `prefixByMilestone` when the update does not name it.
- **Merge per milestone key.** When the update carries `prefixByMilestone`, the stored map
  becomes the *base* map updated with the given map. Each given milestone id is added or
  overwritten. Every stored milestone id that was not given is kept. `{}` changes no entry.
  The base is exactly what `get-run-settings` would return for the field: the stored map
  when it is valid as a whole, otherwise `{}`. A damaged stored map, such as a non-object,
  a blank key, or a bad value, is therefore replaced by the given map and not merged into.
  That way every successful set is visible to the next get. Merging into a damaged map would
  leave the whole field reading `{}`.
- Lists keep their wholesale replacement. The merge applies to `prefixByMilestone` alone.
- No removal: no input removes a milestone id from the map. Removal is out of scope.
- **Refusals.** If `prefixByMilestone` is given and not valid, the helper prints
  `{"ok": false, "error": "prefixByMilestone must be an object of non-empty strings keyed by non-empty milestone ids."}`
  and exits 2. That covers a non-object (`[]`, `"m"`, `null`, `5`, `true`), a blank key
  (`""`, `"  "`), and a value that is not a string or is blank (`""`, `"  "`, `"\t\n"`, `5`,
  `null`, `true`, `["p"]`, `{"x": "p"}`). The existing guarantee holds: every key is checked
  before anything is loaded or written. On a refusal the state file's bytes are unchanged, no
  temp file is left, and no state directory is created when there was none. When several keys
  are bad, the first bad key in input order is reported, as today.
- **Atomic write keeping other keys.** A successful set writes through the existing `save()`
  (`write_atomic`, mode 0600). The write keeps `last_project`, unknown top-level keys, every
  other root's entry, and unknown or damaged fields of ROOT's own entry that the update did
  not name.
- `set-project` keeps a stored `prefixByMilestone`, as it keeps every run setting.
- Run settings stay per root (the root path verbatim). A map set for `/a` does not show
  under `/b` or `/a/`.

### Docstring and usage text

- The module docstring's settings paragraph goes from "six" to "seven". It describes
  `prefixByMilestone` as a map from milestone id to a non-empty prefix string, default `{}`.
  It says that a map given is merged into the stored map per milestone id, while a list
  given still replaces the stored list wholesale.
- The `USAGE` constant and the docstring's command synopsis (`viewer-state.py:5-8,
  35-36`) list only the four subcommands and name no setting. They stay byte for byte, so
  the existing usage test (`tests/core/backend/projects/test_viewer_state.py:115-116`) keeps
  passing. The card's "update the USAGE text" is met by the docstring's settings paragraph,
  which is the helper's only per-setting usage text.

## Tests

All tests are **backend pytest** in `tests/core/backend/projects/test_viewer_state.py`, run
by `bash tests/run.sh`. They belong in that tier because the contract is the helper's command
line, stdout JSON, exit code, and state file bytes. The existing file already drives the real
script as a subprocess against a throwaway `XDG_STATE_HOME`, and the parent spec puts the
round trip there (S7 l.99-101). The change has no QML or JS side, so no QML test is involved.
`tests/architecture` runs unchanged in the same suite.

Changes to existing fixtures:

1. `DEFAULTS` gains `"prefixByMilestone": {}`. Every test that compares a whole reply then
   proves the new field's default.
2. The explicit dict in `test_get_run_settings_reads_a_2_2_entry` gains
   `"prefixByMilestone": {}`. An entry written before this card reads as the default.
3. `test_get_run_settings_with_every_field_damaged_is_defaults` gets a damaged
   `"prefixByMilestone": {"m1": 5}` in its stored entry.
4. The `test_get_run_settings_coerces_each_bad_field_independently` cases gain one row each
   for a stored `prefixByMilestone` of `[]`, `"m"`, `null`, `{"": "p"}`, `{"  ": "p"}`,
   `{"m1": ""}`, `{"m1": "  "}`, `{"m1": 5}`, `{"m1": null}`, `{"m1": ["p"]}`, and a
   good-plus-bad `{"m1": "p", "m2": ""}`. Each row sits next to a valid sibling field, which
   must survive.
5. `BAD_UPDATES` gains the refused `prefixByMilestone` inputs listed under Refusals and a
   good-then-bad mix (`{"parallelism": 2, "prefixByMilestone": {"m1": ""}}`). The two
   parametrised tests then prove exit 2, no directory created, file bytes unchanged, and no
   temp file.
6. `test_dispatch_setting_errors_are_exact_sentences` gains
   `('{"prefixByMilestone": []}', "prefixByMilestone must be an object of non-empty strings keyed by non-empty milestone ids.")`.

New section `# --- prefix by milestone ---` at the end of the file:

- `test_get_prefix_by_milestone_default_is_empty_object`: no file, so `{}`. Checked as
  JSON text: `{}` must not read as `[]` or `null`.
- `test_set_then_get_prefix_by_milestone_round_trips`: two ids set and returned. The other
  fields stay at their defaults.
- `test_set_prefix_by_milestone_merges_per_milestone`: set `{m1: a}`, then `{m2: b}`, giving
  `{m1: a, m2: b}`. Set `{m1: c}`, giving `{m1: c, m2: b}`. Set `{}`, and nothing changes.
- `test_set_prefix_by_milestone_keeps_strings_verbatim`: keys and values with surrounding
  spaces, `/`, and non-ASCII text come back unchanged.
- `test_set_prefix_by_milestone_replaces_a_damaged_stored_map`: stored `{"m1": "p", "m2": 5}`
  plus set `{"m3": "q"}` gives a stored and returned map of `{"m3": "q"}`. The same holds for
  a stored non-object `"x"`.
- `test_other_settings_keep_the_stored_map`: a set of `{"parallelism": 3}` and a set of
  `{"prefixHistory": ["m9"]}` each leave the map unchanged.
- `test_set_prefix_by_milestone_preserves_other_keys`: the state file has `last_project`,
  an unknown top-level key, another root's entry, and an unknown field in ROOT's entry. After
  a merge the file is exactly the expected JSON, with only the map changed. The directory
  holds only `state.json`, which leaves no temp file and so proves the atomic write.
- `test_prefix_by_milestone_refusal_is_exact_and_writes_nothing`: with a valid stored map,
  a bad update returns the exact sentence with exit 2, the bytes are unchanged, and there is
  no temp file.
- `test_prefix_by_milestone_is_per_root`: set under `/a`. `/b` and `/a/` read `{}`.
- `test_set_project_preserves_prefix_by_milestone`.

## Out of scope

- Writing the map after a successful Start, and reading it into the dispatch form. Both
  belong to sibling card `5cf6e2f1`, "2.1 RunStore", which also owns `RunStore.qml` and its
  QML tests.
- How the default prefix is chosen from the map. That is card 1.3, already in
  `core/domain/runs.js`.
- Removing an entry, capping the map's size, and pruning ids of deleted milestones.
- Any change to `prefixHistory` or the other five fields, to `set-project` / `get`, to
  `USAGE`, or to `docs/architecture.md`. Its set-run-settings sentence describes what
  RunStore writes, and that changes with card 2.1.

## Planner handoff

- Files: modify `core/backend/projects/viewer-state.py` (docstring, `RUN_SETTINGS_DEFAULTS`,
  a `valid_prefix_by_milestone` validator, `RUN_SETTINGS_VALID`, `RUN_SETTINGS_REFUSALS`,
  the merge in `cmd_set_run_settings`). Test: `tests/core/backend/projects/test_viewer_state.py`.
- The shared `{}` default in `RUN_SETTINGS_DEFAULTS` must never be mutated. The merge builds
  a new dict, or a copy of the valid stored map, before it updates.
- Suggested tasks: (1) the field: default, validator, refusal sentence, get-side fallback,
  fixtures 1-6, and the docstring; (2) the per-key merge with its damaged-base rule and the
  new section's tests. Each task follows the writing-plans format, with failing tests first.
- Verification: `bash tests/run.sh` (the full suite:
  `bash /home/mtts/.local/state/agent-manager/verify/vfy-opm.sh`).

---

# 1.5 viewer-state.py: prefixByMilestone — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The per-project run settings in `core/backend/projects/viewer-state.py` gain a seventh field, `prefixByMilestone` (milestone id → non-empty prefix string, default `{}`). `get-run-settings` reads it, `set-run-settings` validates it and merges it into the stored map per milestone id.

**Architecture:** One Python helper changed in place. Task 1 adds the field the way the other six are added: an entry in `RUN_SETTINGS_DEFAULTS`, a `valid_prefix_by_milestone` validator in `RUN_SETTINGS_VALID`, and a sentence in `RUN_SETTINGS_REFUSALS`. The existing generic loops then give it get-side fallback and set-side refusal for free, and a set replaces the map wholesale. Task 2 turns that wholesale replacement into a per-key merge inside `cmd_set_run_settings`, with the base being the stored map when it is valid as a whole and `{}` otherwise.

**Tech Stack:** Python 3 standard library only (`json`, `os`, `sys`, plus the repo's `common.atomic_write` and `common.json_line`). Tests are pytest that run the real script as a subprocess against a throwaway `XDG_STATE_HOME`.

**Spec:** `docs/superpowers/specs/1-5-viewer-state-py-02ca6d9d.md` (prepended above).

## Global Constraints

- Field name `prefixByMilestone`, default `{}`.
- Valid value: a JSON object whose every key is a string with a non-whitespace character (`key.strip()`), and whose every value is a string with a non-whitespace character (`value.strip()`). `{}` is valid. No size cap.
- Keys and values are stored and returned verbatim (surrounding whitespace, `/`, non-ASCII). No trimming.
- Refusal sentence, exactly: `prefixByMilestone must be an object of non-empty strings keyed by non-empty milestone ids.`, with exit 2, printed as `{"ok": false, "error": "<sentence>"}`.
- Every key of an update is checked before anything is loaded or written. On a refusal the file bytes are unchanged, no temp file is left, and no state directory is created. With several bad keys, the first bad key in input order is reported.
- `get-run-settings` never writes and never fails, always replies with seven keys, and gives `{}` for a stored map that is not valid as a whole. The other fields fall back independently.
- Merge: the stored map becomes `base` updated with the given map. `base` is the stored map if valid as a whole, otherwise `{}`. No input removes an id. Lists still replace wholesale.
- The shared `{}` in `RUN_SETTINGS_DEFAULTS` is never mutated. The merge builds a new dict.
- `prefixHistory`, its cap of 20 and its sentence, the other five fields, `set-project`, `get`, and `USAGE` stay byte for byte. `docs/architecture.md` is not touched.
- Docstrings and comments state the contract only, with no narrative (no "now", "new", "used to", "no longer").
- `tests/architecture` must pass, and `bash tests/run.sh` must be green.

## Review Focus

1. A map from the legacy `brd-viewer/state.json` (read before any new file exists) followed by a set of another id. A person expects the legacy ids to be kept in the new file, merged with the given one, and the legacy file left untouched. Pinned in `test_set_prefix_by_milestone_merges_into_the_legacy_map` (Task 2).
2. Two ids that differ only by surrounding whitespace (`"m1"` and `" m1"`). A person expects two distinct entries, since keys are verbatim, and not an overwrite. Pinned in `test_set_prefix_by_milestone_padded_ids_are_distinct` (Task 2).
3. A first-ever set of `{"prefixByMilestone": {}}` on a fresh root. A person expects success, a stored `{}`, and a get of the defaults. It must not refuse, and it must not crash on a missing base. Pinned in `test_set_empty_prefix_by_milestone_on_a_fresh_root` (Task 2).
4. A map with many milestones (50 ids). A person expects all of them stored and returned, since the map has no cap, unlike `prefixHistory`. Pinned in `test_prefix_by_milestone_has_no_size_cap` (Task 1).
5. An update whose JSON object names one milestone id twice (`{"m1": "a", "m1": "b"}`). A person expects the last one to win, as in every JSON reader QML uses. Pinned in `test_prefix_by_milestone_duplicate_id_last_wins` (Task 1).

## How to run the tests

The system `python3` may have no pytest. Run it through uv:

- This file: `uv run --with pytest python3 -m pytest tests/core/backend/projects/test_viewer_state.py -q`
- One test: `uv run --with pytest python3 -m pytest "tests/core/backend/projects/test_viewer_state.py::test_set_prefix_by_milestone_merges_per_milestone" -q`
- Everything (pytest tiers including `tests/architecture`, then every QML test): `bash tests/run.sh`. It takes a few minutes, so give it a 10-minute timeout.

Before Task 1 the file has 200 passing tests.

---

### Task 1: the `prefixByMilestone` field (default, validation, refusal, get-side fallback)

**Files:**
- Modify: `core/backend/projects/viewer-state.py:15-23` (docstring settings paragraph), `:38-39` (`RUN_SETTINGS_DEFAULTS`), after `:86` (new `valid_prefix_by_milestone`), `:89-91` (`RUN_SETTINGS_VALID`), `:92-99` (`RUN_SETTINGS_REFUSALS`)
- Test: `tests/core/backend/projects/test_viewer_state.py` (`DEFAULTS` at `:117-118`, coerce cases at `:145-177`, `test_get_run_settings_reads_a_2_2_entry` at `:204-210`, `test_get_run_settings_with_every_field_damaged_is_defaults` at `:219-224`, `BAD_UPDATES` at `:312-326`, `test_dispatch_setting_errors_are_exact_sentences` cases at `:471-475`, new section appended at the end of the file after `:527`)

**Interfaces:**
- Consumes: nothing.
- Produces: `valid_prefix_by_milestone(value) -> bool` in `viewer-state.py`, also registered as `RUN_SETTINGS_VALID["prefixByMilestone"]`. `RUN_SETTINGS_DEFAULTS["prefixByMilestone"] == {}`. `RUN_SETTINGS_REFUSALS["prefixByMilestone"]` is the exact sentence. In the test file: `DEFAULTS` carries `"prefixByMilestone": {}`, and the section `# --- prefix by milestone ---` exists at the end of the file. Task 2 appends to that section and calls `valid_prefix_by_milestone`.

- [ ] **Step 1: Update the existing fixtures (failing tests)**

In `tests/core/backend/projects/test_viewer_state.py`, replace `DEFAULTS` (lines 117-118):

```python
DEFAULTS = {"verify": [], "allowNoVerification": False, "notifyOnEscalation": False,
            "prefixHistory": [], "parallelism": 4, "confirmDispatch": True}
```

with:

```python
DEFAULTS = {"verify": [], "allowNoVerification": False, "notifyOnEscalation": False,
            "prefixHistory": [], "parallelism": 4, "confirmDispatch": True, "prefixByMilestone": {}}
```

In `test_get_run_settings_coerces_each_bad_field_independently`'s parameter list, replace the last case and the closing bracket (lines 175-177):

```python
    ({"verify": "x", "parallelism": 8, "confirmDispatch": False},
     {**DEFAULTS, "parallelism": 8, "confirmDispatch": False}),
])
```

with:

```python
    ({"verify": "x", "parallelism": 8, "confirmDispatch": False},
     {**DEFAULTS, "parallelism": 8, "confirmDispatch": False}),
    ({"prefixByMilestone": [], "parallelism": 8}, {**DEFAULTS, "parallelism": 8}),
    ({"prefixByMilestone": "m", "parallelism": 8}, {**DEFAULTS, "parallelism": 8}),
    ({"prefixByMilestone": None, "parallelism": 8}, {**DEFAULTS, "parallelism": 8}),
    ({"prefixByMilestone": {"": "p"}, "parallelism": 8}, {**DEFAULTS, "parallelism": 8}),
    ({"prefixByMilestone": {"  ": "p"}, "parallelism": 8}, {**DEFAULTS, "parallelism": 8}),
    ({"prefixByMilestone": {"m1": ""}, "parallelism": 8}, {**DEFAULTS, "parallelism": 8}),
    ({"prefixByMilestone": {"m1": "  "}, "parallelism": 8}, {**DEFAULTS, "parallelism": 8}),
    ({"prefixByMilestone": {"m1": 5}, "parallelism": 8}, {**DEFAULTS, "parallelism": 8}),
    ({"prefixByMilestone": {"m1": None}, "parallelism": 8}, {**DEFAULTS, "parallelism": 8}),
    ({"prefixByMilestone": {"m1": ["p"]}, "parallelism": 8}, {**DEFAULTS, "parallelism": 8}),
    ({"prefixByMilestone": {"m1": "p", "m2": ""}, "parallelism": 8}, {**DEFAULTS, "parallelism": 8}),
    ({"prefixByMilestone": {"m1": "p"}, "parallelism": 0},
     {**DEFAULTS, "prefixByMilestone": {"m1": "p"}}),
])
```

In `test_get_run_settings_reads_a_2_2_entry`, replace the `expected` dict (lines 208-209):

```python
    expected = {"verify": ["a"], "allowNoVerification": True, "notifyOnEscalation": True,
                "prefixHistory": [], "parallelism": 4, "confirmDispatch": True}
```

with:

```python
    expected = {"verify": ["a"], "allowNoVerification": True, "notifyOnEscalation": True,
                "prefixHistory": [], "parallelism": 4, "confirmDispatch": True, "prefixByMilestone": {}}
```

In `test_get_run_settings_with_every_field_damaged_is_defaults`, replace the stored entry (lines 220-222):

```python
    write_state(env, {"run_settings": {"/p": {
        "verify": 1, "allowNoVerification": "x", "notifyOnEscalation": None,
        "prefixHistory": [None], "parallelism": True, "confirmDispatch": 0}}})
```

with:

```python
    write_state(env, {"run_settings": {"/p": {
        "verify": 1, "allowNoVerification": "x", "notifyOnEscalation": None,
        "prefixHistory": [None], "parallelism": True, "confirmDispatch": 0, "prefixByMilestone": {"m1": 5}}}})
```

In `BAD_UPDATES`, replace its last line (line 326):

```python
               '{"parallelism": 2, "confirmDispatch": "yes"}']
```

with:

```python
               '{"parallelism": 2, "confirmDispatch": "yes"}',
               '{"prefixByMilestone": []}', '{"prefixByMilestone": "m"}', '{"prefixByMilestone": null}',
               '{"prefixByMilestone": 5}', '{"prefixByMilestone": true}',
               '{"prefixByMilestone": {"": "p"}}', '{"prefixByMilestone": {"  ": "p"}}',
               '{"prefixByMilestone": {"m1": ""}}', '{"prefixByMilestone": {"m1": "  "}}',
               '{"prefixByMilestone": {"m1": "\\t\\n"}}', '{"prefixByMilestone": {"m1": 5}}',
               '{"prefixByMilestone": {"m1": null}}', '{"prefixByMilestone": {"m1": true}}',
               '{"prefixByMilestone": {"m1": ["p"]}}', '{"prefixByMilestone": {"m1": {"x": "p"}}}',
               '{"parallelism": 2, "prefixByMilestone": {"m1": ""}}']
```

In `test_dispatch_setting_errors_are_exact_sentences`'s parameter list, replace (lines 471-475):

```python
@pytest.mark.parametrize("update, error", [
    ('{"prefixHistory": "m3"}', "prefixHistory must be a list of at most 20 non-empty strings."),
    ('{"parallelism": 0}', "parallelism must be a whole number of at least 1."),
    ('{"confirmDispatch": 1}', "confirmDispatch must be true or false."),
])
```

with:

```python
@pytest.mark.parametrize("update, error", [
    ('{"prefixHistory": "m3"}', "prefixHistory must be a list of at most 20 non-empty strings."),
    ('{"parallelism": 0}', "parallelism must be a whole number of at least 1."),
    ('{"confirmDispatch": 1}', "confirmDispatch must be true or false."),
    ('{"prefixByMilestone": []}',
     "prefixByMilestone must be an object of non-empty strings keyed by non-empty milestone ids."),
])
```

- [ ] **Step 2: Append the new section's field tests (failing tests)**

At the very end of `tests/core/backend/projects/test_viewer_state.py` (after `test_set_parallelism_huge_values`), append:

```python


# --- prefix by milestone -----------------------------------------------------------

BY_MILESTONE_REFUSAL = "prefixByMilestone must be an object of non-empty strings keyed by non-empty milestone ids."


def set_by_milestone(env, root, by_milestone):
    return run(env, "set-run-settings", root, json.dumps({"prefixByMilestone": by_milestone}, ensure_ascii=False))


def test_get_prefix_by_milestone_default_is_empty_object(env):
    code, result = run(env, "get-run-settings", "/p")
    # JSON text: {} must not read as [] or null.
    assert code == 0 and len(result) == 7 and json.dumps(result["prefixByMilestone"]) == "{}"


def test_set_then_get_prefix_by_milestone_round_trips(env):
    by_milestone = {"m1": "feat/m1", "8a3c0f12": "m2-"}
    assert set_by_milestone(env, "/p", by_milestone) == (0, {"ok": True})
    code, result = run(env, "get-run-settings", "/p")
    assert code == 0 and same_json(result, {**DEFAULTS, "prefixByMilestone": by_milestone})


def test_set_prefix_by_milestone_keeps_strings_verbatim(env):
    by_milestone = {"  m1  ": "  feat/x  ", "café": "日本/", "a/b": "m3"}
    assert set_by_milestone(env, "/p", by_milestone) == (0, {"ok": True})
    assert run(env, "get-run-settings", "/p")[1]["prefixByMilestone"] == by_milestone


def test_prefix_by_milestone_has_no_size_cap(env):
    by_milestone = {"m%d" % i: "p%d" % i for i in range(50)}
    assert set_by_milestone(env, "/p", by_milestone) == (0, {"ok": True})
    assert run(env, "get-run-settings", "/p")[1]["prefixByMilestone"] == by_milestone


def test_prefix_by_milestone_duplicate_id_last_wins(env):
    assert run(env, "set-run-settings", "/p", '{"prefixByMilestone": {"m1": "a", "m1": "b"}}') == (0, {"ok": True})
    assert run(env, "get-run-settings", "/p")[1]["prefixByMilestone"] == {"m1": "b"}


def test_other_settings_keep_the_stored_map(env):
    assert set_by_milestone(env, "/p", {"m1": "a"}) == (0, {"ok": True})
    for update in ({"parallelism": 3}, {"prefixHistory": ["m9"]}):
        assert run(env, "set-run-settings", "/p", json.dumps(update)) == (0, {"ok": True})
        assert run(env, "get-run-settings", "/p")[1]["prefixByMilestone"] == {"m1": "a"}, update
    assert json.loads(state_file(env).read_text())["run_settings"]["/p"] == {
        "prefixByMilestone": {"m1": "a"}, "parallelism": 3, "prefixHistory": ["m9"]}


@pytest.mark.parametrize("update", ['{"prefixByMilestone": []}', '{"prefixByMilestone": {"m2": ""}}',
                                    '{"prefixByMilestone": {"": "p"}}', '{"prefixByMilestone": {"m2": 5}}',
                                    '{"parallelism": 2, "prefixByMilestone": {"m2": "  "}}'])
def test_prefix_by_milestone_refusal_is_exact_and_writes_nothing(env, update):
    write_state(env, {"run_settings": {"/p": {"prefixByMilestone": {"m1": "a"}}}})
    before = state_file(env).read_bytes()
    assert run(env, "set-run-settings", "/p", update) == (2, {"ok": False, "error": BY_MILESTONE_REFUSAL})
    assert state_file(env).read_bytes() == before
    assert [p.name for p in state_file(env).parent.iterdir()] == ["state.json"]


def test_prefix_by_milestone_first_bad_key_in_input_order_is_reported(env):
    assert run(env, "set-run-settings", "/p", '{"prefixByMilestone": [], "parallelism": 0}') == (
        2, {"ok": False, "error": BY_MILESTONE_REFUSAL})
    assert run(env, "set-run-settings", "/p", '{"parallelism": 0, "prefixByMilestone": []}') == (
        2, {"ok": False, "error": "parallelism must be a whole number of at least 1."})
    assert not Path(env["XDG_STATE_HOME"]).exists()


def test_prefix_by_milestone_is_per_root(env):
    assert set_by_milestone(env, "/a", {"m1": "a-"}) == (0, {"ok": True})
    assert run(env, "get-run-settings", "/a")[1]["prefixByMilestone"] == {"m1": "a-"}
    for root in ("/b", "/a/"):
        code, result = run(env, "get-run-settings", root)
        assert code == 0 and same_json(result, DEFAULTS), root


def test_set_project_preserves_prefix_by_milestone(env):
    assert set_by_milestone(env, "/p", {"m1": "a", "m2": "b"}) == (0, {"ok": True})
    assert run(env, "set-project", "/other") == (0, {"ok": True})
    assert run(env, "get-run-settings", "/p")[1]["prefixByMilestone"] == {"m1": "a", "m2": "b"}
    assert run(env, "get") == (0, {"last_project": "/other"})
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/projects/test_viewer_state.py -q`
Expected: FAIL. Every test that compares against `DEFAULTS` fails because the reply has no `prefixByMilestone` key. The new `prefixByMilestone` `BAD_UPDATES` rows fail with `Unknown run setting: prefixByMilestone.` in place of a refusal on the field (some still pass, since that message also exits 2). The round-trip, verbatim, size-cap, duplicate-id, other-settings, per-root and set-project tests fail with exit 2 `Unknown run setting`. The exact-sentence rows fail on the message.

- [ ] **Step 4: Implement the field**

In `core/backend/projects/viewer-state.py`, replace the docstring's settings paragraph (lines 15-23):

```python
any other keys already in the file. Run settings live under "run_settings", keyed
by the root path verbatim. There are six, each read on its own:
verify (a list of non-empty strings, default []), allowNoVerification and
notifyOnEscalation (booleans, default false), prefixHistory (a list of at most 20
non-empty strings, most recent first, default []), parallelism (a whole number
>= 1, default 4) and confirmDispatch (a boolean, default true).
`set-run-settings` takes a JSON object with any of them, validates every key
before writing anything, and changes only the keys given; a list given replaces
the stored list wholesale.
"""
```

with:

```python
any other keys already in the file. Run settings live under "run_settings", keyed
by the root path verbatim. There are seven, each read on its own:
verify (a list of non-empty strings, default []), allowNoVerification and
notifyOnEscalation (booleans, default false), prefixHistory (a list of at most 20
non-empty strings, most recent first, default []), parallelism (a whole number
>= 1, default 4), confirmDispatch (a boolean, default true) and prefixByMilestone
(an object mapping each milestone id to a non-empty prefix string, default {}).
`set-run-settings` takes a JSON object with any of them, validates every key
before writing anything, and changes only the keys given; a list given replaces
the stored list wholesale.
"""
```

Replace `RUN_SETTINGS_DEFAULTS` (lines 38-39):

```python
RUN_SETTINGS_DEFAULTS = {"verify": [], "allowNoVerification": False, "notifyOnEscalation": False,
                         "prefixHistory": [], "parallelism": 4, "confirmDispatch": True}
```

with:

```python
RUN_SETTINGS_DEFAULTS = {"verify": [], "allowNoVerification": False, "notifyOnEscalation": False,
                         "prefixHistory": [], "parallelism": 4, "confirmDispatch": True,
                         "prefixByMilestone": {}}
```

Directly after `valid_boolean` (after line 86, before the blank lines that precede `RUN_SETTINGS_VALID`), add:

```python


def valid_prefix_by_milestone(value):
    return isinstance(value, dict) and all(
        key.strip() and isinstance(prefix, str) and prefix.strip() for key, prefix in value.items())
```

(JSON object keys are always strings, so `key.strip()` needs no type check.)

Replace `RUN_SETTINGS_VALID` and `RUN_SETTINGS_REFUSALS` (lines 89-99):

```python
RUN_SETTINGS_VALID = {"verify": valid_verify, "allowNoVerification": valid_boolean,
                      "notifyOnEscalation": valid_boolean, "prefixHistory": valid_prefix_history,
                      "parallelism": valid_parallelism, "confirmDispatch": valid_boolean}
RUN_SETTINGS_REFUSALS = {
    "verify": "verify must be a list of non-empty strings.",
    "allowNoVerification": "allowNoVerification must be true or false.",
    "notifyOnEscalation": "notifyOnEscalation must be true or false.",
    "prefixHistory": "prefixHistory must be a list of at most %d non-empty strings." % PREFIX_HISTORY_CAP,
    "parallelism": "parallelism must be a whole number of at least 1.",
    "confirmDispatch": "confirmDispatch must be true or false.",
}
```

with:

```python
RUN_SETTINGS_VALID = {"verify": valid_verify, "allowNoVerification": valid_boolean,
                      "notifyOnEscalation": valid_boolean, "prefixHistory": valid_prefix_history,
                      "parallelism": valid_parallelism, "confirmDispatch": valid_boolean,
                      "prefixByMilestone": valid_prefix_by_milestone}
RUN_SETTINGS_REFUSALS = {
    "verify": "verify must be a list of non-empty strings.",
    "allowNoVerification": "allowNoVerification must be true or false.",
    "notifyOnEscalation": "notifyOnEscalation must be true or false.",
    "prefixHistory": "prefixHistory must be a list of at most %d non-empty strings." % PREFIX_HISTORY_CAP,
    "parallelism": "parallelism must be a whole number of at least 1.",
    "confirmDispatch": "confirmDispatch must be true or false.",
    "prefixByMilestone": "prefixByMilestone must be an object of non-empty strings keyed by non-empty milestone ids.",
}
```

`cmd_get_run_settings` and `parse_run_settings` already loop over these tables, so they need no change. `USAGE` is not touched.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/projects/test_viewer_state.py -q`
Expected: PASS, no failures.

- [ ] **Step 6: Commit**

```bash
git add core/backend/projects/viewer-state.py tests/core/backend/projects/test_viewer_state.py
git commit -m "feat(projects): viewer-state.py stores prefixByMilestone in the run settings"
```

---

### Task 2: `set-run-settings` merges `prefixByMilestone` per milestone id

**Files:**
- Modify: `core/backend/projects/viewer-state.py` (docstring's last settings sentence, edited in Task 1; `cmd_set_run_settings`, originally lines 150-162)
- Test: `tests/core/backend/projects/test_viewer_state.py` (append to the `# --- prefix by milestone ---` section at the end of the file)

**Interfaces:**
- Consumes: `valid_prefix_by_milestone(value) -> bool` (Task 1). Test helpers from Task 1: `set_by_milestone(env, root, by_milestone) -> (int, dict)`, `same_json(actual, expected) -> bool`, `DEFAULTS` with `"prefixByMilestone": {}`, `write_state(env, content)`, `state_file(env) -> Path`.
- Produces: `cmd_set_run_settings(root_path, text) -> int`, same signature, merging `prefixByMilestone`. Nothing else depends on it.

- [ ] **Step 1: Write the merge tests (failing tests)**

Append to the end of `tests/core/backend/projects/test_viewer_state.py`:

```python


def test_set_prefix_by_milestone_merges_per_milestone(env):
    def set_and_get(by_milestone):
        assert set_by_milestone(env, "/p", by_milestone) == (0, {"ok": True})
        return run(env, "get-run-settings", "/p")[1]["prefixByMilestone"]
    assert set_and_get({"m1": "a"}) == {"m1": "a"}
    assert set_and_get({"m2": "b"}) == {"m1": "a", "m2": "b"}
    assert set_and_get({"m1": "c"}) == {"m1": "c", "m2": "b"}
    assert set_and_get({}) == {"m1": "c", "m2": "b"}


def test_set_prefix_by_milestone_padded_ids_are_distinct(env):
    assert set_by_milestone(env, "/p", {"m1": "a"}) == (0, {"ok": True})
    assert set_by_milestone(env, "/p", {" m1": "b"}) == (0, {"ok": True})
    assert run(env, "get-run-settings", "/p")[1]["prefixByMilestone"] == {"m1": "a", " m1": "b"}


# A damaged stored map is replaced, not merged into: merging would leave a bad
# entry behind and the whole field would read {}.
@pytest.mark.parametrize("stored", [{"m1": "p", "m2": 5}, "x", [], {"": "p"}, None])
def test_set_prefix_by_milestone_replaces_a_damaged_stored_map(env, stored):
    write_state(env, {"run_settings": {"/p": {"verify": ["a"], "prefixByMilestone": stored}}})
    assert set_by_milestone(env, "/p", {"m3": "q"}) == (0, {"ok": True})
    assert json.loads(state_file(env).read_text())["run_settings"]["/p"] == {
        "verify": ["a"], "prefixByMilestone": {"m3": "q"}}
    code, result = run(env, "get-run-settings", "/p")
    assert code == 0 and same_json(result, {**DEFAULTS, "verify": ["a"], "prefixByMilestone": {"m3": "q"}})


def test_set_empty_prefix_by_milestone_on_a_fresh_root(env):
    assert set_by_milestone(env, "/p", {}) == (0, {"ok": True})
    assert json.loads(state_file(env).read_text()) == {"run_settings": {"/p": {"prefixByMilestone": {}}}}
    code, result = run(env, "get-run-settings", "/p")
    assert code == 0 and same_json(result, DEFAULTS)


def test_set_prefix_by_milestone_preserves_other_keys(env):
    write_state(env, {"last_project": "/p", "other": {"x": 1},
                      "run_settings": {"/q": {"prefixByMilestone": {"m1": "q-"}},
                                       "/p": {"verify": ["old"], "future": 1, "parallelism": "x",
                                              "prefixByMilestone": {"m1": "a"}}}})
    assert set_by_milestone(env, "/p", {"m2": "b"}) == (0, {"ok": True})
    assert json.loads(state_file(env).read_text()) == {
        "last_project": "/p", "other": {"x": 1},
        "run_settings": {"/q": {"prefixByMilestone": {"m1": "q-"}},
                         "/p": {"verify": ["old"], "future": 1, "parallelism": "x",
                                "prefixByMilestone": {"m1": "a", "m2": "b"}}}}
    assert [p.name for p in state_file(env).parent.iterdir()] == ["state.json"]


def test_set_prefix_by_milestone_merges_into_the_legacy_map(env):
    old = Path(env["XDG_STATE_HOME"]) / "brd-viewer" / "state.json"
    old.parent.mkdir(parents=True)
    old.write_text('{"run_settings": {"/p": {"prefixByMilestone": {"m1": "a"}}}}')
    assert set_by_milestone(env, "/p", {"m2": "b"}) == (0, {"ok": True})
    assert json.loads(state_file(env).read_text()) == {
        "run_settings": {"/p": {"prefixByMilestone": {"m1": "a", "m2": "b"}}}}
    assert old.read_text() == '{"run_settings": {"/p": {"prefixByMilestone": {"m1": "a"}}}}'
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/projects/test_viewer_state.py -q -k "merges or padded or damaged_stored or fresh_root or preserves_other_keys"`
Expected: FAIL for `test_set_prefix_by_milestone_merges_per_milestone` (second assertion: `{'m2': 'b'} != {'m1': 'a', 'm2': 'b'}`), `test_set_prefix_by_milestone_padded_ids_are_distinct`, `test_set_prefix_by_milestone_preserves_other_keys`, and `test_set_prefix_by_milestone_merges_into_the_legacy_map`. These already PASS, since Task 1's wholesale replacement satisfies them: `test_set_prefix_by_milestone_replaces_a_damaged_stored_map` (all five), `test_set_empty_prefix_by_milestone_on_a_fresh_root`, and the older `test_set_run_settings_preserves_other_keys` / `test_set_dispatch_settings_preserves_other_keys`. They are guards that the merge must keep green: a naive merge into a damaged map fails the first.

- [ ] **Step 3: Implement the merge**

In `core/backend/projects/viewer-state.py`, replace the last two lines of the docstring's settings paragraph (as left by Task 1):

```python
before writing anything, and changes only the keys given; a list given replaces
the stored list wholesale.
"""
```

with:

```python
before writing anything, and changes only the keys given; a list given replaces
the stored list wholesale, and a prefixByMilestone given is merged into the
stored map per milestone id (a stored map that is not valid is replaced).
"""
```

Replace `cmd_set_run_settings`:

```python
def cmd_set_run_settings(root_path, text):
    update, error = parse_run_settings(text)
    if update is None:
        return emit({"ok": False, "error": error}, 2)
    data = load()
    settings = data.get("run_settings")
    if not isinstance(settings, dict):
        settings = data["run_settings"] = {}
    entry = settings.get(root_path)
    if not isinstance(entry, dict):
        entry = settings[root_path] = {}
    entry.update(update)
    return save(data)
```

with:

```python
def cmd_set_run_settings(root_path, text):
    update, error = parse_run_settings(text)
    if update is None:
        return emit({"ok": False, "error": error}, 2)
    data = load()
    settings = data.get("run_settings")
    if not isinstance(settings, dict):
        settings = data["run_settings"] = {}
    entry = settings.get(root_path)
    if not isinstance(entry, dict):
        entry = settings[root_path] = {}
    if "prefixByMilestone" in update:
        stored = entry.get("prefixByMilestone")
        merged = dict(stored) if valid_prefix_by_milestone(stored) else {}
        merged.update(update["prefixByMilestone"])
        update["prefixByMilestone"] = merged
    entry.update(update)
    return save(data)
```

`merged` is always a new dict, so neither the stored map nor `RUN_SETTINGS_DEFAULTS["prefixByMilestone"]` is mutated.

- [ ] **Step 4: Run the file's tests to verify they pass**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/projects/test_viewer_state.py -q`
Expected: PASS, no failures.

- [ ] **Step 5: Run the full suite**

Run: `bash tests/run.sh` (10-minute timeout)
Expected: pytest reports no failures (including `tests/architecture`), every QML file prints a `Totals:` line with `0 failed`, and the exit status is 0.

- [ ] **Step 6: Commit**

```bash
git add core/backend/projects/viewer-state.py tests/core/backend/projects/test_viewer_state.py
git commit -m "feat(projects): set-run-settings merges prefixByMilestone per milestone id"
```

---

## Self-review (planner)

1. **Spec coverage.**
   - Field name and `{}` default: Task 1 `DEFAULTS` and `test_get_prefix_by_milestone_default_is_empty_object`.
   - Validity rule with `.strip()`, `{}` valid, no cap, verbatim strings: Task 1 validator, `test_prefix_by_milestone_has_no_size_cap`, `test_set_prefix_by_milestone_keeps_strings_verbatim`, `test_set_empty_prefix_by_milestone_on_a_fresh_root`.
   - Get with seven keys, `{}` for a missing or damaged file: `len(result) == 7` and the existing bad-file tests via `DEFAULTS`.
   - An invalid-as-a-whole stored map gives `{}` with siblings unaffected: fixture 4 rows, including a valid map beside a bad sibling.
   - Every field damaged: fixture 3. A pre-card entry: fixture 2. Strict JSON output: the existing test via `DEFAULTS`.
   - Set accepted alongside other keys, partial update: `test_other_settings_keep_the_stored_map`.
   - Merge per key, `{}` changes nothing: `test_set_prefix_by_milestone_merges_per_milestone`.
   - Damaged base replaced: `test_set_prefix_by_milestone_replaces_a_damaged_stored_map`.
   - Lists still replace wholesale: the existing `test_set_prefix_history_replaces_the_list`. No removal: no input path removes, and the merge only adds or overwrites.
   - Refusals, the exact sentence, first bad key in input order, nothing written, no temp file, no directory: fixtures 5-6, `test_prefix_by_milestone_refusal_is_exact_and_writes_nothing`, `test_prefix_by_milestone_first_bad_key_in_input_order_is_reported`.
   - Atomic write keeping other keys: `test_set_prefix_by_milestone_preserves_other_keys`. Mode 0600 on a new file: the existing `test_new_state_file_from_run_settings_is_private` (`write_atomic` keeps an existing file's mode).
   - `set-project` keeps the map: `test_set_project_preserves_prefix_by_milestone`. Per root: `test_prefix_by_milestone_is_per_root`.
   - Docstring "seven", the map's description and the merge sentence: Task 1 Step 4 and Task 2 Step 3. `USAGE` is untouched, and the existing usage test keeps it.
   - Shared default never mutated: `dict(stored)` or `{}` is always a fresh dict.
   - Verification and `tests/architecture`: Task 2 Step 5.
2. **Placeholders.** None. Every code step carries the full replacement text.
3. **Type consistency.** `valid_prefix_by_milestone(value) -> bool` is defined in Task 1 and used in Task 2. `set_by_milestone(env, root, by_milestone)` and `BY_MILESTONE_REFUSAL` are defined in Task 1 Step 2 and used in Task 2. `same_json` already exists in the dispatch section, above the new section.
4. **Review Focus.** Each of its five lines has a pinning test in the owning task, named in the line.
<!-- task-pipeline: validated -->
