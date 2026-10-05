# 2.3 viewer-state.py: dispatch settings (card fdb5feb1)

Narrowed from `docs/superpowers/specs/2026-10-03-am-run-dispatch-design.md` (S3):
"Dispatch levels" defaults bullet (lines 76-79: "Verify and parallelism = last
values used for this project, from the per-project store below"), the
"Confirm dispatches" bullet (lines 82-85) and "Architecture", the per-project
dispatch settings bullet (lines 113-117: "S3 adds fields to that store; it does
not create a second one"). Parent story d3d879b9 ("Dispatch backend"). Blocked
by 299ec9c0 (2.2 `start-run.py`), which is on this branch; nothing in it is
touched.

The store being extended was specified by
`docs/superpowers/specs/2-2-viewer-state-py-per-a36aac36.md` (S2 card a36aac36,
commit f7d589f). Every rule of that spec not changed below still holds and its
tests keep passing.

## Starting point

- `core/backend/projects/viewer-state.py` holds `get`, `set-project`,
  `get-run-settings <root>` and `set-run-settings <root> <json>`.
  `RUN_SETTINGS_DEFAULTS` (line 32) has three keys: `verify` (`[]`),
  `allowNoVerification` (`false`), `notifyOnEscalation` (`false`).
- `cmd_get_run_settings` (lines 75-82) resolves each known key independently,
  falling back to its default when the stored value is damaged.
- `parse_run_settings` (lines 85-100) refuses non-JSON, non-objects, unknown keys
  (`Unknown run setting: <key>.`), a bad `verify`
  (`verify must be a list of non-empty strings.`) and **any other key that is not
  a boolean** (`<key> must be true or false.`). That last branch is wrong for
  `parallelism` and `prefixHistory`: validation must become per key.
- `cmd_set_run_settings` (lines 120-132) validates fully before loading or
  writing, then merges only the given keys into the root's entry.
- `core/domain/runs.js` `dispatchDefaults` (lines ~885-895) already reads
  `settings.parallelism` as "a whole number >= 1, else 4", and
  `validateDispatch` refuses any other parallelism with
  "Parallelism must be a whole number of at least 1". This card mirrors that
  rule on the storage side.
- Tests: `tests/core/backend/projects/test_viewer_state.py`, subprocess harness
  (`env`, `run(env, *args) -> (code, last JSON line)`, `state_file`,
  `write_state`), module-level `DEFAULTS` (line ~117) and `BAD_UPDATES`
  (line ~245).

## Scope

Two files only:

- `core/backend/projects/viewer-state.py`: three new run-settings keys, per-key
  validation in `set-run-settings`, per-key coercion in `get-run-settings`, and
  the module docstring.
- `tests/core/backend/projects/test_viewer_state.py`: new tests, plus the
  `DEFAULTS` constant and the existing literal get-output dicts extended with the
  three new defaults (see "Existing tests").

Tests first.

### Out of scope

- `core/stores/RunStore.qml`: reading these settings into the dispatch form,
  writing them back at Start, and recording a used prefix into the history. That
  is card 3.1 (66a6b6c0, "settings persisted via set-run-settings").
- `ui/components/DispatchDialog.qml` and the "Confirm dispatches" toggle, and
  what turning it off does (only removes the extra confirm click, never the
  preview or the warning, parent lines 82-85). That is cards 4.1 (dfc0ac87) and
  4.2 (46141e11). This card only stores the flag.
- `core/domain/runs.js`: `dispatchDefaults` / `validateDispatch` are done
  (cards 5eb7ec0c, 45cc9067) and unchanged. Using the prefix history as a prefix
  default belongs to a later milestone (card aba87499).
- `prefixByMilestone` (card 02ca6d9d) and `get-global-settings` /
  `set-global-settings` (card 25dbf867): later milestones' fields in this same
  file.
- `dispatch-preview.py`, `start-run.py` (cards a19ca446, 299ec9c0): unchanged.
- The `USAGE` string: unchanged (it lists subcommands, not keys).
- `docs/architecture.md`: no change.
- The stray extra blank line after the imports: not touched.

## Behaviour

### Settings and defaults

Per project root, six settings. The first three are unchanged from 2.2.

| key | type | default | meaning |
|---|---|---|---|
| `verify` | list of non-empty strings | `[]` | unchanged |
| `allowNoVerification` | boolean | `false` | unchanged |
| `notifyOnEscalation` | boolean | `false` | unchanged |
| `prefixHistory` | list of at most 20 non-empty strings | `[]` | branch prefixes used to dispatch in this project, most recent first |
| `parallelism` | whole number >= 1 | `4` | the parallelism last used for this project (`--parallelism`) |
| `confirmDispatch` | boolean | `true` | "Confirm dispatches"; **on by default** (parent line 82) |

The parent spec calls "Confirm dispatches" a per-viewer setting (line 82) but
lists it among the per-project dispatch settings (line 113-114); the card says
to extend the per-project run settings, and this spec follows the card and line
113, as 2.2 did for `notifyOnEscalation`.

`confirmDispatch` is the first setting whose default is `true`: a project with
no stored entry, or a damaged stored value, reads `true`.

### Design decisions the parent leaves open

The parent says only "prefix history" (line 113). This spec fixes:

- **Shape:** a list of strings, each non-empty and not only whitespace, stored
  verbatim (no trimming), at most **20** entries. Order is meaningful: the
  first entry is the most recent. The cap keeps a per-project history from
  growing without bound in a file that is rewritten on every set.
- **Ownership of the policy:** the helper is a store, not a history manager. It
  does not reorder, deduplicate, prepend or trim; the caller (RunStore, card 3.1)
  sends the whole new list. A list over the cap is **refused**, not truncated,
  so a caller bug is loud rather than silently losing entries.
- **Update:** `prefixHistory` in a `set-run-settings` update **replaces** the
  stored list wholesale, like `verify`. `{"prefixHistory": []}` clears it.

For `parallelism`:

- A JSON integer >= 1. JSON booleans are refused (in Python `True` is an `int`).
  Any JSON number written with a fraction or exponent (`2.0`, `1.5`, `4e0`,
  `1e400`) is refused, as are `NaN` / `Infinity`: the helper only accepts what
  `JSON.stringify` of a JS whole number produces. No upper bound (runs.js has
  none; `am` judges the value).

### `get-run-settings <root_path>`

Unchanged contract (one JSON line, **always exit 0**, legacy-file fallback, only
known keys echoed), now with exactly six keys:

```json
{"verify": [], "allowNoVerification": false, "notifyOnEscalation": false,
 "prefixHistory": [], "parallelism": 4, "confirmDispatch": true}
```

Each key resolves independently from the root's stored entry:

- `prefixHistory`: the stored value if it is a list of at most 20 elements,
  every one a string that is not empty or only whitespace; otherwise `[]`. A
  partially valid or over-long list is **not** filtered or truncated: the whole
  value falls back to `[]` (same rule as `verify`).
- `parallelism`: the stored value if it is a JSON integer (not a boolean, not a
  float, even `2.0`) and >= 1; otherwise `4`.
- `confirmDispatch`: the stored value only if it is a JSON boolean (`0`, `1`,
  `"false"`, `null` are not); otherwise `true`.
- A file, `run_settings` or entry that is missing or not an object: all six
  defaults (as today, now including `confirmDispatch: true`).
- An entry written by 2.2 (only the first three keys): those three as stored,
  the new three as defaults.

### `set-run-settings <root_path> <json>`

Unchanged contract (partial update, validation strictly before any load or
write, exit 2 with `{"ok": false, "error": "<sentence>"}` on refusal leaving the
file byte-for-byte unchanged or absent, atomic `0o600` write, other top-level
keys / other roots / unknown keys inside the entry preserved, `OSError` exits 1,
damaged stored fields not given in the update are left as stored). Changes:

- `prefixHistory`, `parallelism` and `confirmDispatch` are known keys; any
  subset of the six may be given.
- Each key is validated by its own rule. Refusal sentences, exact:
  - `prefixHistory must be a list of at most 20 non-empty strings.` (not a list,
    more than 20 elements, a non-string element, an empty or whitespace-only
    element)
  - `parallelism must be a whole number of at least 1.` (`0`, `-1`, `1.5`,
    `2.0`, `"4"`, `true`, `null`, `NaN`, `Infinity`, a list)
  - `confirmDispatch must be true or false.` (`1`, `"true"`, `null`)
  - the existing sentences for `verify`, the two older booleans, unknown keys,
    non-JSON and non-object input are unchanged.
- When several keys are bad, the error names the first bad key in the order the
  update object lists them (unchanged behaviour: keys are checked in input
  order).
- Accepted values are stored exactly as given: prefix strings verbatim
  (surrounding spaces, `/`, non-ASCII kept), the history's order and duplicates
  kept, `parallelism` as the integer given (no cap).

### Module docstring

States the six keys with their types and defaults (or at least: `verify` a list
of non-empty strings; `prefixHistory` a list of at most 20 non-empty strings,
most recent first, replaced wholesale; `parallelism` a whole number >= 1,
default 4; `allowNoVerification`, `notifyOnEscalation` booleans default false;
`confirmDispatch` boolean default true). States the contract only, no history
of which milestone added what. The file stays ASCII.

## Tests

Tier for every test below: **backend pytest, subprocess**, in
`tests/core/backend/projects/test_viewer_state.py` (parent "Testing" bullet 3,
lines 154-156; 2.2 spec "Tests"). Why this tier: the helper's contract is argv
in, one JSON line, an exit code and a file on disk out. There is no Qt and no
`am`, so the existing `env`/`run`/`state_file`/`write_state` harness exercises
it end to end against a throwaway `XDG_STATE_HOME`; no mocks. No QML tier: no
QML changes. Architecture tier (`tests/architecture`, existing, unchanged) must
stay green: no redefinition of `emit` / `write_atomic`, stdlib-only imports,
ASCII source.

`DEFAULTS` becomes
`{"verify": [], "allowNoVerification": False, "notifyOnEscalation": False, "prefixHistory": [], "parallelism": 4, "confirmDispatch": True}`.

### Existing tests

Every existing test keeps its inputs and its intent. The only edits allowed:

- `DEFAULTS` as above (every `DEFAULTS` / `{**DEFAULTS, ...}` comparison then
  covers the new keys automatically).
- Literal expected get outputs that spell out the three old keys
  (`test_get_run_settings_reads_the_legacy_file`,
  `test_set_then_get_run_settings_round_trips`,
  `test_set_run_settings_is_partial`, `test_run_settings_are_per_root`,
  `test_set_project_preserves_run_settings`) are rewritten as
  `{**DEFAULTS, ...}` with the same old-key values, or have the three new
  defaults added. For the two that set a full object and compare it back
  (`round_trips`, `set_project_preserves_run_settings`), the comparison must
  still be exact equality of all keys. No assertion is weakened or deleted.
- New entries appended to `BAD_UPDATES` (below), so the existing
  `test_set_run_settings_rejects_bad_json` and
  `test_set_run_settings_rejection_leaves_the_file_untouched` cover them.

### New tests

Get:

1. `test_get_run_settings_dispatch_defaults` — no file: `parallelism` is `4`,
   `confirmDispatch` is `true` (compared as JSON text so `1` cannot pass for
   `true`), `prefixHistory` is `[]`. (Also covered by the updated
   `test_get_run_settings_with_no_file_is_defaults`; this one names the card's
   headline default, `confirmDispatch` true, explicitly.)
2. `test_get_run_settings_reads_a_2_2_entry` — a stored entry with only
   `verify: ["a"]`, `allowNoVerification: true`, `notifyOnEscalation: true`:
   those values plus `prefixHistory []`, `parallelism 4`,
   `confirmDispatch true`.
3. Extend the parametrisation of
   `test_get_run_settings_coerces_each_bad_field_independently` (compared as
   JSON text) with, each next to one valid sibling field that must survive:
   - `prefixHistory`: `"m3"`, `["m3", 5]`, `["m3", ""]`, `["  "]`, `null`, a
     list of 21 valid strings -> `[]`;
   - `parallelism`: `0`, `-2`, `1.5`, `2.0`, `"4"`, `true`, `null`, `[4]` -> `4`;
   - `confirmDispatch`: `0`, `1`, `"false"`, `null` -> `true`;
   - and the reverse: a damaged old field (`verify: "x"`) next to valid
     `parallelism: 8` and `confirmDispatch: false`, which are returned.
4. `test_get_run_settings_accepts_a_history_of_exactly_twenty` — a stored list
   of 20 valid strings is returned unchanged, in order.

Set:

5. `test_set_then_get_dispatch_settings_round_trips` — set
   `{"prefixHistory": ["m3", "m2"], "parallelism": 2, "confirmDispatch": false}`:
   `(0, {"ok": True})`; get returns `{**DEFAULTS, ...those...}` exactly (JSON
   text compare, so `false` is a boolean and `2` an integer).
6. `test_set_dispatch_settings_is_partial` — set `{"verify": ["a"],
   "notifyOnEscalation": true}`, then `{"parallelism": 6}`, then
   `{"confirmDispatch": false}`, then `{"prefixHistory": ["m3"]}`: after each
   step every previously set key still reads back as set; finally
   `{"verify": ["b"]}` leaves all three dispatch keys unchanged.
7. `test_set_prefix_history_replaces_the_list` — set `["m1", "m2", "m3"]`, then
   `["m4"]`: get gives `["m4"]` (not merged); then `[]`: get gives `[]`.
8. `test_set_prefix_history_keeps_strings_verbatim` — `["  m3  ", "feat/x",
   "café", "m3", "m3"]` (spaces, slash, non-ASCII, duplicates): read back
   identical, same order.
9. `test_set_prefix_history_of_exactly_twenty_is_accepted` — 20 strings: exit 0
   and round trip; 21 strings: exit 2 with the exact `prefixHistory` sentence
   and the file untouched.
10. `test_set_parallelism_has_no_upper_bound` — `{"parallelism": 1}` and
    `{"parallelism": 1000}` both round-trip as integers.
11. `test_dispatch_setting_errors_are_exact_sentences` — parametrised:
    `{"prefixHistory": "m3"}` ->
    `prefixHistory must be a list of at most 20 non-empty strings.`;
    `{"parallelism": 0}` -> `parallelism must be a whole number of at least 1.`;
    `{"confirmDispatch": 1}` -> `confirmDispatch must be true or false.`;
    each with exit 2 and `ok` false.
12. `test_first_bad_key_in_input_order_is_reported` — `{"parallelism": 0,
    "confirmDispatch": 1}` names `parallelism`; `{"confirmDispatch": 1,
    "parallelism": 0}` names `confirmDispatch`.
13. `test_set_dispatch_settings_preserves_other_keys` — file with
    `last_project`, another root's entry, and this root's entry holding
    `verify ["old"]`, `"future": 1` and a damaged `parallelism: "x"`: setting
    `{"confirmDispatch": false}` changes only that key in the file (raw file
    JSON compared), `parallelism` still stored as `"x"` and read as `4`.
14. `test_dispatch_settings_are_per_root` — `/a` with `parallelism 2`,
    `confirmDispatch false`, `prefixHistory ["a1"]`; `/b` untouched: `/b` and
    `/a/` read `DEFAULTS`.

Refusals, appended to `BAD_UPDATES` (each: exit 2, `ok` false, non-empty
`error`; no file created when none existed; existing file byte-identical and
no temp files):

15. `prefixHistory`: `{"prefixHistory": "m3"}`,
    `{"prefixHistory": {"m3": 1}}`, `{"prefixHistory": [1]}`,
    `{"prefixHistory": [""]}`, `{"prefixHistory": ["  "]}`,
    `{"prefixHistory": null}`, a 21-element list.
16. `parallelism`: `0`, `-1`, `1.5`, `2.0`, `4e0`, `"4"`, `true`, `null`,
    `NaN`, `Infinity`, `[4]`.
17. `confirmDispatch`: `1`, `0`, `"true"`, `null`.
18. A valid dispatch key next to a bad one (`{"parallelism": 2,
    "confirmDispatch": "yes"}`): refused as a whole, nothing written.

Verification: `bash tests/run.sh` green.

## Review focus (inputs most likely to bite, for the planner)

1. `true` for `parallelism`: Python's `isinstance(True, int)` is true, so a
   naive integer check accepts it on set and returns it on get. Must be refused
   on set and read as `4` on get.
2. `confirmDispatch` default is `true`: any code path that falls back to
   "falsy" (`entry.get(key, False)`, a shared bool loop with a wrong default)
   silently turns confirmation off for every project with no stored value.
3. A partial update of one dispatch key must not wipe `verify` (S2's Resume
   depends on it) nor any other dispatch key; and a refused update must not
   touch the file.
4. `2.0` / `1e0` / `NaN` / `Infinity` for `parallelism` arrive as Python floats
   from `json.loads`; they must be refused on set and read as `4` on get, and
   the get output must never contain a float or a non-standard JSON token.
5. A `prefixHistory` over the cap or with one bad element is refused or read as
   `[]` whole, never truncated or filtered.

---

# viewer-state.py dispatch settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three per-project run settings to `core/backend/projects/viewer-state.py`: `prefixHistory` (list of at most 20 non-empty strings, default `[]`), `parallelism` (whole number >= 1, default `4`) and `confirmDispatch` (boolean, default `true`). Each key gets its own validation in `set-run-settings` and its own coercion in `get-run-settings`. Tests come first, in `tests/core/backend/projects/test_viewer_state.py`.

**Architecture:** Everything stays in the one stdlib-only script. One table, `RUN_SETTINGS_VALID` (key -> predicate), replaces the hard-coded `verify` / boolean branches. `get-run-settings` loops over `RUN_SETTINGS_DEFAULTS` and keeps a stored value only when its key's predicate accepts it (Task 1). `set-run-settings` checks each update key against the same predicate and, on refusal, prints that key's sentence from a second table, `RUN_SETTINGS_REFUSALS` (Task 2). The load / merge / atomic-write path does not change.

**Tech Stack:** Python 3 stdlib (`json`, `os`, `sys`), `common.atomic_write.write_atomic`, `common.json_line.emit`, and pytest, which runs the script as a subprocess.

**Spec:** `docs/superpowers/specs/2-3-viewer-state-py-fdb5feb1.md` (prepended above). Parent design: `docs/superpowers/specs/2026-10-03-am-run-dispatch-design.md` (S3). Store originally specified by `docs/superpowers/specs/2-2-viewer-state-py-per-a36aac36.md`.

**Worktree / branch:** all paths are relative to `/home/mtts/Code/omarchy-project-manager/.claude/worktrees/dsp/task-2-3-viewer-state-py-fdb5feb1`, on branch `dsp/task-2-3-viewer-state-py-fdb5feb1`. Run every command from that directory.

**Running pytest:** `python3` here is a uv-managed interpreter without pytest (see `tests/run.sh`), so every pytest command below is written as `uv run --with pytest python3 -m pytest ...`. Before this plan starts, `tests/core/backend/projects/test_viewer_state.py` plus `tests/architecture` gives `115 passed`.

## Global Constraints

- `get-run-settings` prints exactly six keys: `verify`, `allowNoVerification`, `notifyOnEscalation`, `prefixHistory`, `parallelism`, `confirmDispatch`. It always exits 0.
- Defaults: `verify` `[]`, `allowNoVerification` `false`, `notifyOnEscalation` `false`, `prefixHistory` `[]`, `parallelism` `4`, `confirmDispatch` `true`.
- `prefixHistory` cap: **20** entries. A longer list is refused on set and read as `[]` on get. It is never truncated or filtered.
- `parallelism`: a JSON integer >= 1. Booleans, floats (`2.0`, `4e0`, `1e400`), `NaN` and `Infinity` are refused on set and read as `4` on get. There is no upper bound.
- Refusal sentences, exact:
  - `prefixHistory must be a list of at most 20 non-empty strings.`
  - `parallelism must be a whole number of at least 1.`
  - `confirmDispatch must be true or false.`
  - The existing sentences are unchanged: `verify must be a list of non-empty strings.`, `<key> must be true or false.`, `Unknown run setting: <key>.`, `The run settings are not valid JSON.`, `The run settings must be a JSON object.`
- Keys are checked in the order the update object lists them, and the first bad one is reported. Validation finishes before any load or write. A refused update leaves the file byte-for-byte unchanged (or absent), exits 2 and prints `{"ok": false, "error": ...}`.
- Accepted values are stored exactly as given: strings verbatim, list order and duplicates kept. A list value replaces the stored list wholesale.
- `write_atomic` and `emit` are imported, never redefined. The script imports only the stdlib and `common`. `viewer-state.py` and the test file stay ASCII, so non-ASCII in tests is written as `\uXXXX` escapes.
- Do not change `USAGE`, the stray third blank line after the imports (lines 27-29), `get`, `set-project`, `docs/architecture.md`, `RunStore.qml`, `runs.js` or any other file.
- Existing tests keep their inputs and intent. The only edits allowed are to `DEFAULTS`, the five literal get-output dicts named in the spec, and new entries in `BAD_UPDATES`. No assertion is weakened or deleted.
- Verification: `bash tests/run.sh` green.

## Review Focus

The spec's own five review-focus inputs are pinned by its numbered tests:
- `true` for parallelism: `BAD_UPDATES` plus the get coercion params.
- confirmDispatch defaulting to true: `test_get_run_settings_dispatch_defaults`.
- Partial and refused updates: `test_set_dispatch_settings_is_partial` and the `BAD_UPDATES` rejection tests.
- Floats and NaN: `BAD_UPDATES` plus the get coercion params.
- Over-cap and partly-bad history: the get coercion params and `test_set_prefix_history_of_exactly_twenty_is_accepted`.

The spec implies five more inputs that none of its numbered tests exercise. Each one has a test in the task that owns the code:

1. **`set-project` running between dispatch-setting writes.** RunStore calls `set-project` every time the user switches project. It must keep `prefixHistory`, `parallelism` and `confirmDispatch` exactly as stored. Pinned by `test_set_project_preserves_dispatch_settings` (Task 2).
2. **A hand-edited or foreign state file holding `NaN`, `Infinity`, `-Infinity`, `1e400` or `2.0` as `parallelism`.** Python's `json` reads all of them. `get-run-settings` must print `4`, and its stdout must be strict JSON that QML's `JSON.parse` accepts, with no `NaN` token and no float. Pinned by `test_get_run_settings_output_is_strict_json` (Task 1).
3. **A `parallelism` too long to parse (more than 4300 digits), and a large one that does parse (`10**30`).** The first must be a clean refusal: exit 2, `The run settings are not valid JSON.`, no traceback, no file. The second round-trips as an integer, because there is no cap. Pinned by `test_set_parallelism_huge_values` (Task 2).
4. **Whitespace that is not a space, and negative zero.** A `prefixHistory` entry of only tab and newline (`["\t\n"]`) is refused like `["  "]`. `{"parallelism": -0}` is refused like `0`. Pinned by two extra `BAD_UPDATES` entries (Task 2).
5. **A stored entry where every one of the six fields is damaged at once.** Get must give exactly the defaults, including `confirmDispatch: true`, and must not let one bad field leak into another key's fallback. Pinned by `test_get_run_settings_with_every_field_damaged_is_defaults` (Task 1).

## File Structure

- Modify: `core/backend/projects/viewer-state.py`.
  - Task 1: `RUN_SETTINGS_DEFAULTS` (line 32) gets three new keys and a new constant, `PREFIX_HISTORY_CAP`. New predicates follow `valid_verify` (lines 65-66): `valid_prefix_history`, `valid_parallelism`, `valid_boolean`, plus the table `RUN_SETTINGS_VALID`. `cmd_get_run_settings` (lines 75-82) becomes one loop.
  - Task 2: a new table, `RUN_SETTINGS_REFUSALS`. The loop in `parse_run_settings` (lines 93-99) and the module docstring (lines 1-19) are rewritten.
- Modify: `tests/core/backend/projects/test_viewer_state.py`.
  - Task 1: `DEFAULTS` (line 117), the five literal get outputs, extra params in `test_get_run_settings_coerces_each_bad_field_independently`, and new get tests.
  - Task 2: new `BAD_UPDATES` entries and new set tests appended at the end of the file.

No other file changes.

---

### Task 1: `get-run-settings` returns the three dispatch settings

**Files:**
- Modify: `core/backend/projects/viewer-state.py:32` (`RUN_SETTINGS_DEFAULTS`), `:65-66` (after `valid_verify`), `:75-82` (`cmd_get_run_settings`)
- Test: `tests/core/backend/projects/test_viewer_state.py:117`, `:144-155`, `:167-172`, `:185-198`, `:207-215`, `:228-232`, plus new tests inserted after line 172

**Interfaces:**
- Consumes: the existing `load() -> dict`, `run_settings_entry(data, root_path) -> dict`, `valid_verify(value) -> bool`, `emit(payload, code) -> int`. Test harness: `env`, `run(env, *args) -> (int, dict | None)`, `state_file(env)`, `write_state(env, content)`, `SCRIPT`.
- Produces (Task 2 relies on these names):
  - `PREFIX_HISTORY_CAP = 20`
  - `RUN_SETTINGS_DEFAULTS = {"verify": [], "allowNoVerification": False, "notifyOnEscalation": False, "prefixHistory": [], "parallelism": 4, "confirmDispatch": True}`. Its keys are the set of known keys.
  - `valid_prefix_history(value) -> bool`, `valid_parallelism(value) -> bool`, `valid_boolean(value) -> bool`
  - `RUN_SETTINGS_VALID: dict[str, callable]`, one predicate per key of `RUN_SETTINGS_DEFAULTS`
  - Tests: `DEFAULTS` with the six keys

- [ ] **Step 1: Update `DEFAULTS` and the five literal get outputs in the test file**

In `tests/core/backend/projects/test_viewer_state.py`, replace line 117:

```python
DEFAULTS = {"verify": [], "allowNoVerification": False, "notifyOnEscalation": False}
```

with:

```python
DEFAULTS = {"verify": [], "allowNoVerification": False, "notifyOnEscalation": False,
            "prefixHistory": [], "parallelism": 4, "confirmDispatch": True}
```

Replace the last two lines of `test_get_run_settings_reads_the_legacy_file` (lines 171-172):

```python
    assert run(env, "get-run-settings", "/p") == (
        0, {"verify": ["make check"], "allowNoVerification": True, "notifyOnEscalation": False})
```

with:

```python
    assert run(env, "get-run-settings", "/p") == (
        0, {**DEFAULTS, "verify": ["make check"], "allowNoVerification": True, "notifyOnEscalation": False})
```

In `test_set_then_get_run_settings_round_trips`, replace line 188:

```python
    assert run(env, "get-run-settings", "/p") == (0, settings)
```

with:

```python
    assert run(env, "get-run-settings", "/p") == (0, {**DEFAULTS, **settings})
```

Replace the whole body of `test_set_run_settings_is_partial` (lines 192-198) with:

```python
    assert run(env, "set-run-settings", "/p", '{"verify": ["a"]}') == (0, {"ok": True})
    assert run(env, "set-run-settings", "/p", '{"notifyOnEscalation": true}') == (0, {"ok": True})
    assert run(env, "get-run-settings", "/p") == (
        0, {**DEFAULTS, "verify": ["a"], "allowNoVerification": False, "notifyOnEscalation": True})
    assert run(env, "set-run-settings", "/p", '{"verify": []}') == (0, {"ok": True})
    assert run(env, "get-run-settings", "/p") == (
        0, {**DEFAULTS, "verify": [], "allowNoVerification": False, "notifyOnEscalation": True})
```

In `test_run_settings_are_per_root`, replace lines 210-213:

```python
    assert run(env, "get-run-settings", "/a") == (
        0, {"verify": ["make a"], "allowNoVerification": False, "notifyOnEscalation": True})
    assert run(env, "get-run-settings", "/home/u/my proj") == (
        0, {"verify": ["make b"], "allowNoVerification": True, "notifyOnEscalation": False})
```

with:

```python
    assert run(env, "get-run-settings", "/a") == (
        0, {**DEFAULTS, "verify": ["make a"], "allowNoVerification": False, "notifyOnEscalation": True})
    assert run(env, "get-run-settings", "/home/u/my proj") == (
        0, {**DEFAULTS, "verify": ["make b"], "allowNoVerification": True, "notifyOnEscalation": False})
```

In `test_set_project_preserves_run_settings`, replace line 232:

```python
    assert run(env, "get-run-settings", "/p") == (0, stored)
```

with:

```python
    assert run(env, "get-run-settings", "/p") == (0, {**DEFAULTS, **stored})
```

All of these are still exact `==` comparisons of the whole dict. They now also pin the three new defaults.

- [ ] **Step 2: Extend the get coercion parametrisation**

In `test_get_run_settings_coerces_each_bad_field_independently`, add these rows after the last existing row (`({"notifyOnEscalation": "yes", "allowNoVerification": True}, ...),`, line 154) and before the closing `])`. Each row pairs one damaged dispatch field with one valid sibling that must survive. The last row is the reverse: a damaged old field next to valid dispatch fields.

```python
    ({"prefixHistory": "m3", "confirmDispatch": False}, {**DEFAULTS, "confirmDispatch": False}),
    ({"prefixHistory": ["m3", 5], "confirmDispatch": False}, {**DEFAULTS, "confirmDispatch": False}),
    ({"prefixHistory": ["m3", ""], "confirmDispatch": False}, {**DEFAULTS, "confirmDispatch": False}),
    ({"prefixHistory": ["  "], "confirmDispatch": False}, {**DEFAULTS, "confirmDispatch": False}),
    ({"prefixHistory": None, "confirmDispatch": False}, {**DEFAULTS, "confirmDispatch": False}),
    ({"prefixHistory": ["m%d" % i for i in range(21)], "confirmDispatch": False},
     {**DEFAULTS, "confirmDispatch": False}),
    ({"parallelism": 0, "prefixHistory": ["m3"]}, {**DEFAULTS, "prefixHistory": ["m3"]}),
    ({"parallelism": -2, "prefixHistory": ["m3"]}, {**DEFAULTS, "prefixHistory": ["m3"]}),
    ({"parallelism": 1.5, "prefixHistory": ["m3"]}, {**DEFAULTS, "prefixHistory": ["m3"]}),
    ({"parallelism": 2.0, "prefixHistory": ["m3"]}, {**DEFAULTS, "prefixHistory": ["m3"]}),
    ({"parallelism": "4", "prefixHistory": ["m3"]}, {**DEFAULTS, "prefixHistory": ["m3"]}),
    ({"parallelism": True, "prefixHistory": ["m3"]}, {**DEFAULTS, "prefixHistory": ["m3"]}),
    ({"parallelism": None, "prefixHistory": ["m3"]}, {**DEFAULTS, "prefixHistory": ["m3"]}),
    ({"parallelism": [4], "prefixHistory": ["m3"]}, {**DEFAULTS, "prefixHistory": ["m3"]}),
    ({"confirmDispatch": 0, "parallelism": 8}, {**DEFAULTS, "parallelism": 8}),
    ({"confirmDispatch": 1, "parallelism": 8}, {**DEFAULTS, "parallelism": 8}),
    ({"confirmDispatch": "false", "parallelism": 8}, {**DEFAULTS, "parallelism": 8}),
    ({"confirmDispatch": None, "parallelism": 8}, {**DEFAULTS, "parallelism": 8}),
    ({"verify": "x", "parallelism": 8, "confirmDispatch": False},
     {**DEFAULTS, "parallelism": 8, "confirmDispatch": False}),
```

The test already compares `json.dumps(result, sort_keys=True)` with `json.dumps(expected, sort_keys=True)`. So a stored `2.0` leaking through prints `2.0`, not `4`, and `1` leaking through as `confirmDispatch` prints `1`, not `true`. Both fail.

- [ ] **Step 3: Write the new get tests**

Insert these after `test_get_run_settings_reads_the_legacy_file`, which ends at line 172 before Step 1's edit, and before the `@pytest.mark.parametrize("args", [` that precedes `test_run_settings_bad_usage_is_rejected`. Keep two blank lines between functions.

```python
def test_get_run_settings_dispatch_defaults(env):
    code, result = run(env, "get-run-settings", "/p")
    assert code == 0
    # JSON text, so a 1 cannot pass for true nor 4.0 for 4.
    assert json.dumps([result["prefixHistory"], result["parallelism"], result["confirmDispatch"]]) == '[[], 4, true]'


def test_get_run_settings_reads_a_2_2_entry(env):
    write_state(env, {"run_settings": {"/p": {"verify": ["a"], "allowNoVerification": True,
                                              "notifyOnEscalation": True}}})
    code, result = run(env, "get-run-settings", "/p")
    expected = {"verify": ["a"], "allowNoVerification": True, "notifyOnEscalation": True,
                "prefixHistory": [], "parallelism": 4, "confirmDispatch": True}
    assert code == 0 and json.dumps(result, sort_keys=True) == json.dumps(expected, sort_keys=True)


def test_get_run_settings_accepts_a_history_of_exactly_twenty(env):
    twenty = ["m%d" % i for i in range(20)]
    write_state(env, {"run_settings": {"/p": {"prefixHistory": twenty}}})
    assert run(env, "get-run-settings", "/p") == (0, {**DEFAULTS, "prefixHistory": twenty})


def test_get_run_settings_with_every_field_damaged_is_defaults(env):
    write_state(env, {"run_settings": {"/p": {
        "verify": 1, "allowNoVerification": "x", "notifyOnEscalation": None,
        "prefixHistory": [None], "parallelism": True, "confirmDispatch": 0}}})
    code, result = run(env, "get-run-settings", "/p")
    assert code == 0 and json.dumps(result, sort_keys=True) == json.dumps(DEFAULTS, sort_keys=True)


def reject_token(token):
    raise ValueError("not strict JSON: %s" % token)


# A stored NaN, Infinity or float must not reach QML's JSON.parse: the output is
# parsed here with every non-standard constant and every float refused.
@pytest.mark.parametrize("stored", ["NaN", "Infinity", "-Infinity", "1e400", "2.0"])
def test_get_run_settings_output_is_strict_json(env, stored):
    write_state(env, '{"run_settings": {"/p": {"parallelism": %s}}}' % stored)
    proc = subprocess.run([sys.executable, SCRIPT, "get-run-settings", "/p"], env=env, capture_output=True, text=True)
    assert proc.returncode == 0
    result = json.loads(proc.stdout, parse_constant=reject_token, parse_float=reject_token)
    assert result == DEFAULTS
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/projects/test_viewer_state.py -q`
Expected: FAIL, with many failures. Every test that compares a get output with `DEFAULTS` or `{**DEFAULTS, ...}` fails, because get still prints only three keys (for example `test_get_run_settings_with_no_file_is_defaults` and `test_get_run_settings_treats_bad_files_as_defaults`). So do the new rows of `test_get_run_settings_coerces_each_bad_field_independently` and the five new tests (the strict-JSON one fails on `result == DEFAULTS`). The `set-project` / `get` tests and the set-rejection tests still pass.

- [ ] **Step 5: Implement the defaults, predicates and the get loop**

In `core/backend/projects/viewer-state.py`, replace line 32:

```python
RUN_SETTINGS_DEFAULTS = {"verify": [], "allowNoVerification": False, "notifyOnEscalation": False}
```

with:

```python
PREFIX_HISTORY_CAP = 20
RUN_SETTINGS_DEFAULTS = {"verify": [], "allowNoVerification": False, "notifyOnEscalation": False,
                         "prefixHistory": [], "parallelism": 4, "confirmDispatch": True}
```

Replace `valid_verify` (lines 65-66):

```python
def valid_verify(value):
    return isinstance(value, list) and all(isinstance(v, str) and v.strip() for v in value)
```

with:

```python
def valid_verify(value):
    return isinstance(value, list) and all(isinstance(v, str) and v.strip() for v in value)


def valid_prefix_history(value):
    return valid_verify(value) and len(value) <= PREFIX_HISTORY_CAP


def valid_parallelism(value):
    # type(), not isinstance(): True is an int, and 2.0, NaN and Infinity are floats.
    return type(value) is int and value >= 1


def valid_boolean(value):
    return isinstance(value, bool)


RUN_SETTINGS_VALID = {"verify": valid_verify, "allowNoVerification": valid_boolean,
                      "notifyOnEscalation": valid_boolean, "prefixHistory": valid_prefix_history,
                      "parallelism": valid_parallelism, "confirmDispatch": valid_boolean}
```

Replace `cmd_get_run_settings`. It currently reads:

```python
def cmd_get_run_settings(root_path):
    entry = run_settings_entry(load(), root_path)
    verify = entry.get("verify")
    result = {"verify": verify if valid_verify(verify) else []}
    for key in ("allowNoVerification", "notifyOnEscalation"):
        value = entry.get(key)
        result[key] = value if isinstance(value, bool) else RUN_SETTINGS_DEFAULTS[key]
    return emit(result, 0)
```

Replace it with:

```python
def cmd_get_run_settings(root_path):
    entry = run_settings_entry(load(), root_path)
    result = {}
    for key, default in RUN_SETTINGS_DEFAULTS.items():
        value = entry.get(key)
        result[key] = value if RUN_SETTINGS_VALID[key](value) else default
    return emit(result, 0)
```

Leave `parse_run_settings` alone in this task. It now treats the three new keys as known, with the old boolean rule, and Task 2 replaces that rule.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/projects/test_viewer_state.py tests/architecture -q`
Expected: all pass, 0 failed.

- [ ] **Step 7: Commit**

```bash
git add core/backend/projects/viewer-state.py tests/core/backend/projects/test_viewer_state.py
git commit -m "viewer-state.py: get-run-settings returns prefixHistory, parallelism and confirmDispatch, each coerced on its own (S3 2.3)"
```

---

### Task 2: `set-run-settings` validates each key by its own rule, and the docstring

**Files:**
- Modify: `core/backend/projects/viewer-state.py:1-19` (docstring), after `RUN_SETTINGS_VALID` (new `RUN_SETTINGS_REFUSALS`), `parse_run_settings` loop (lines 93-99 before Task 1, now shifted down by Task 1's insertions)
- Test: `tests/core/backend/projects/test_viewer_state.py`: `BAD_UPDATES` (the `BAD_UPDATES = [...]` assignment), plus new tests appended at the end of the file

**Interfaces:**
- Consumes (from Task 1): `PREFIX_HISTORY_CAP`, `RUN_SETTINGS_DEFAULTS`, `RUN_SETTINGS_VALID`, the predicates, and test `DEFAULTS`. Existing: `parse_run_settings(text) -> (dict | None, str | None)`, `cmd_set_run_settings`, `save`. Test harness: `env`, `run`, `state_file`, `write_state`.
- Produces: `RUN_SETTINGS_REFUSALS: dict[str, str]`, one refusal sentence per key of `RUN_SETTINGS_DEFAULTS`. Nothing later depends on it.

- [ ] **Step 1: Extend `BAD_UPDATES`**

In `tests/core/backend/projects/test_viewer_state.py`, replace the whole `BAD_UPDATES` assignment:

```python
BAD_UPDATES = ["", "{", "[]", '"x"', "null", "5", '{"allow_no_verification": true}', '{"verify": "pytest"}',
               '{"verify": [1]}', '{"verify": [""]}', '{"verify": ["  "]}', '{"allowNoVerification": "true"}',
               '{"notifyOnEscalation": 1}', '{"notifyOnEscalation": null}', '{"verify": ["a"], "bogus": 1}',
               pytest.param("[" * 100000, id="nested-past-the-recursion-limit")]
```

with:

```python
BAD_UPDATES = ["", "{", "[]", '"x"', "null", "5", '{"allow_no_verification": true}', '{"verify": "pytest"}',
               '{"verify": [1]}', '{"verify": [""]}', '{"verify": ["  "]}', '{"allowNoVerification": "true"}',
               '{"notifyOnEscalation": 1}', '{"notifyOnEscalation": null}', '{"verify": ["a"], "bogus": 1}',
               pytest.param("[" * 100000, id="nested-past-the-recursion-limit"),
               '{"prefixHistory": "m3"}', '{"prefixHistory": {"m3": 1}}', '{"prefixHistory": [1]}',
               '{"prefixHistory": [""]}', '{"prefixHistory": ["  "]}', '{"prefixHistory": null}',
               '{"prefixHistory": ["\\t\\n"]}',
               pytest.param(json.dumps({"prefixHistory": ["m%d" % i for i in range(21)]}), id="prefix-history-of-21"),
               '{"parallelism": 0}', '{"parallelism": -1}', '{"parallelism": -0}', '{"parallelism": 1.5}',
               '{"parallelism": 2.0}', '{"parallelism": 4e0}', '{"parallelism": 1e400}', '{"parallelism": "4"}',
               '{"parallelism": true}', '{"parallelism": null}', '{"parallelism": NaN}', '{"parallelism": Infinity}',
               '{"parallelism": -Infinity}', '{"parallelism": [4]}',
               '{"confirmDispatch": 1}', '{"confirmDispatch": 0}', '{"confirmDispatch": "true"}',
               '{"confirmDispatch": null}',
               '{"parallelism": 2, "confirmDispatch": "yes"}']
```

(`'{"prefixHistory": ["\\t\\n"]}'` is the Python text of the JSON `{"prefixHistory": ["\t\n"]}`. The JSON string decodes to a tab and a newline, which is whitespace only.)

The existing `test_set_run_settings_rejects_bad_json` and `test_set_run_settings_rejection_leaves_the_file_untouched` now cover every new entry.

- [ ] **Step 2: Write the new set tests**

Append to the end of `tests/core/backend/projects/test_viewer_state.py`, after `test_run_settings_root_is_any_non_empty_string`, with two blank lines before the first new line:

```python
# --- dispatch settings -------------------------------------------------------------

def same_json(actual, expected):
    """JSON text equality: 1 is not true, 2.0 is not 2."""
    return json.dumps(actual, sort_keys=True) == json.dumps(expected, sort_keys=True)


def test_set_then_get_dispatch_settings_round_trips(env):
    settings = {"prefixHistory": ["m3", "m2"], "parallelism": 2, "confirmDispatch": False}
    assert run(env, "set-run-settings", "/p", json.dumps(settings)) == (0, {"ok": True})
    code, result = run(env, "get-run-settings", "/p")
    assert code == 0 and same_json(result, {**DEFAULTS, **settings})


def test_set_dispatch_settings_is_partial(env):
    expected = dict(DEFAULTS)
    for update in ({"verify": ["a"], "notifyOnEscalation": True}, {"parallelism": 6}, {"confirmDispatch": False},
                   {"prefixHistory": ["m3"]}, {"verify": ["b"]}):
        assert run(env, "set-run-settings", "/p", json.dumps(update)) == (0, {"ok": True})
        expected.update(update)
        code, result = run(env, "get-run-settings", "/p")
        assert code == 0 and same_json(result, expected), update
    assert expected["parallelism"] == 6 and expected["confirmDispatch"] is False
    assert expected["prefixHistory"] == ["m3"]


def test_set_prefix_history_replaces_the_list(env):
    assert run(env, "set-run-settings", "/p", '{"prefixHistory": ["m1", "m2", "m3"]}') == (0, {"ok": True})
    assert run(env, "set-run-settings", "/p", '{"prefixHistory": ["m4"]}') == (0, {"ok": True})
    assert run(env, "get-run-settings", "/p")[1]["prefixHistory"] == ["m4"]
    assert run(env, "set-run-settings", "/p", '{"prefixHistory": []}') == (0, {"ok": True})
    assert run(env, "get-run-settings", "/p")[1]["prefixHistory"] == []


def test_set_prefix_history_keeps_strings_verbatim(env):
    history = ["  m3  ", "feat/x", "caf\u00e9", "m3", "m3"]
    assert run(env, "set-run-settings", "/p", json.dumps({"prefixHistory": history}, ensure_ascii=False)) == (
        0, {"ok": True})
    assert run(env, "get-run-settings", "/p")[1]["prefixHistory"] == history


def test_set_prefix_history_of_exactly_twenty_is_accepted(env):
    twenty = ["m%d" % i for i in range(20)]
    assert run(env, "set-run-settings", "/p", json.dumps({"prefixHistory": twenty})) == (0, {"ok": True})
    assert run(env, "get-run-settings", "/p")[1]["prefixHistory"] == twenty
    before = state_file(env).read_bytes()
    assert run(env, "set-run-settings", "/p", json.dumps({"prefixHistory": twenty + ["m20"]})) == (
        2, {"ok": False, "error": "prefixHistory must be a list of at most 20 non-empty strings."})
    assert state_file(env).read_bytes() == before
    assert [p.name for p in state_file(env).parent.iterdir()] == ["state.json"]


@pytest.mark.parametrize("value", [1, 1000])
def test_set_parallelism_has_no_upper_bound(env, value):
    assert run(env, "set-run-settings", "/p", json.dumps({"parallelism": value})) == (0, {"ok": True})
    code, result = run(env, "get-run-settings", "/p")
    assert code == 0 and json.dumps(result["parallelism"]) == str(value)


@pytest.mark.parametrize("update, error", [
    ('{"prefixHistory": "m3"}', "prefixHistory must be a list of at most 20 non-empty strings."),
    ('{"parallelism": 0}', "parallelism must be a whole number of at least 1."),
    ('{"confirmDispatch": 1}', "confirmDispatch must be true or false."),
])
def test_dispatch_setting_errors_are_exact_sentences(env, update, error):
    assert run(env, "set-run-settings", "/p", update) == (2, {"ok": False, "error": error})


def test_first_bad_key_in_input_order_is_reported(env):
    assert run(env, "set-run-settings", "/p", '{"parallelism": 0, "confirmDispatch": 1}') == (
        2, {"ok": False, "error": "parallelism must be a whole number of at least 1."})
    assert run(env, "set-run-settings", "/p", '{"confirmDispatch": 1, "parallelism": 0}') == (
        2, {"ok": False, "error": "confirmDispatch must be true or false."})


def test_set_dispatch_settings_preserves_other_keys(env):
    write_state(env, {"last_project": "/p",
                      "run_settings": {"/q": {"parallelism": 3},
                                       "/p": {"verify": ["old"], "future": 1, "parallelism": "x"}}})
    assert run(env, "set-run-settings", "/p", '{"confirmDispatch": false}') == (0, {"ok": True})
    assert json.loads(state_file(env).read_text()) == {
        "last_project": "/p",
        "run_settings": {"/q": {"parallelism": 3},
                         "/p": {"verify": ["old"], "future": 1, "parallelism": "x", "confirmDispatch": False}}}
    code, result = run(env, "get-run-settings", "/p")
    assert code == 0 and same_json(result, {**DEFAULTS, "verify": ["old"], "confirmDispatch": False})


def test_dispatch_settings_are_per_root(env):
    assert run(env, "set-run-settings", "/a",
               '{"parallelism": 2, "confirmDispatch": false, "prefixHistory": ["a1"]}') == (0, {"ok": True})
    code, result = run(env, "get-run-settings", "/a")
    assert code == 0 and same_json(result, {**DEFAULTS, "parallelism": 2, "confirmDispatch": False,
                                            "prefixHistory": ["a1"]})
    for root in ("/b", "/a/"):
        code, result = run(env, "get-run-settings", root)
        assert code == 0 and same_json(result, DEFAULTS), root


def test_set_project_preserves_dispatch_settings(env):
    stored = {"prefixHistory": ["m3", "m2"], "parallelism": 3, "confirmDispatch": False}
    assert run(env, "set-run-settings", "/p", json.dumps(stored)) == (0, {"ok": True})
    assert run(env, "set-project", "/other") == (0, {"ok": True})
    code, result = run(env, "get-run-settings", "/p")
    assert code == 0 and same_json(result, {**DEFAULTS, **stored})
    assert run(env, "get") == (0, {"last_project": "/other"})


def test_set_parallelism_huge_values(env):
    # Python refuses to parse an integer of more than 4300 digits: a clean refusal, no traceback.
    assert run(env, "set-run-settings", "/p", '{"parallelism": 1%s}' % ("0" * 5000)) == (
        2, {"ok": False, "error": "The run settings are not valid JSON."})
    assert not Path(env["XDG_STATE_HOME"]).exists()
    assert run(env, "set-run-settings", "/p", json.dumps({"parallelism": 10 ** 30})) == (0, {"ok": True})
    code, result = run(env, "get-run-settings", "/p")
    assert code == 0 and json.dumps(result["parallelism"]) == str(10 ** 30)
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/projects/test_viewer_state.py -q`
Expected: FAIL. `parse_run_settings` still applies `<key> must be true or false.` to every key other than `verify`, so:
- Every set of a list `prefixHistory` or an integer `parallelism` is refused. That fails `round_trips`, `is_partial`, `replaces_the_list`, `keeps_strings_verbatim`, `of_exactly_twenty_is_accepted`, `has_no_upper_bound`, `are_per_root`, `set_project_preserves_dispatch_settings` and `huge_values`.
- `test_dispatch_setting_errors_are_exact_sentences` fails for `prefixHistory` and `parallelism`, whose sentence is wrong.
- `test_first_bad_key_in_input_order_is_reported` fails on its first assertion.
- Both `BAD_UPDATES` tests fail for `{"parallelism": true}`, which is a boolean and so is accepted.

Some new tests already pass, which is expected because the old boolean rule happens to give the right outcome for them: `test_set_dispatch_settings_preserves_other_keys` (it sets only `confirmDispatch: false`), the `confirmDispatch` row of the exact-sentences test, and the other new `BAD_UPDATES` rows.

- [ ] **Step 4: Implement per-key validation**

In `core/backend/projects/viewer-state.py`, directly after the `RUN_SETTINGS_VALID = {...}` assignment added in Task 1, add (two blank lines before it):

```python
RUN_SETTINGS_REFUSALS = {
    "verify": "verify must be a list of non-empty strings.",
    "allowNoVerification": "allowNoVerification must be true or false.",
    "notifyOnEscalation": "notifyOnEscalation must be true or false.",
    "prefixHistory": "prefixHistory must be a list of at most %d non-empty strings." % PREFIX_HISTORY_CAP,
    "parallelism": "parallelism must be a whole number of at least 1.",
    "confirmDispatch": "confirmDispatch must be true or false.",
}
```

In `parse_run_settings`, replace the loop:

```python
    for key, value in update.items():
        if key not in RUN_SETTINGS_DEFAULTS:
            return None, "Unknown run setting: %s." % key
        if key == "verify" and not valid_verify(value):
            return None, "verify must be a list of non-empty strings."
        if key != "verify" and not isinstance(value, bool):
            return None, "%s must be true or false." % key
    return update, None
```

with:

```python
    for key, value in update.items():
        if key not in RUN_SETTINGS_DEFAULTS:
            return None, "Unknown run setting: %s." % key
        if not RUN_SETTINGS_VALID[key](value):
            return None, RUN_SETTINGS_REFUSALS[key]
    return update, None
```

`cmd_set_run_settings` does not change. It still validates first, then loads, merges with `entry.update(update)` and saves.

- [ ] **Step 5: Update the module docstring**

Replace lines 1-19 of `core/backend/projects/viewer-state.py` (the shebang line stays):

```python
#!/usr/bin/env python3
"""Remembers which brd project the panel was last showing, and each project's
run settings.

    viewer-state.py get
    viewer-state.py set-project <root_path>
    viewer-state.py get-run-settings <root_path>
    viewer-state.py set-run-settings <root_path> <json>

State lives in ${XDG_STATE_HOME:-~/.local/state}/omarchy-project-manager/state.json
(reads fall back to the old brd-viewer/state.json until a new one is written). QML
cannot write files, hence this helper. Prints one JSON line. `get` and
`get-run-settings` never fail (a missing or corrupt file, or a damaged value, just
means the default); `set-project` and `set-run-settings` write atomically and keep
any other keys already in the file. Run settings live under "run_settings", keyed
by the root path verbatim: `set-run-settings` takes a JSON object with any of
verify (a list of non-empty strings), allowNoVerification and notifyOnEscalation
(booleans), validates it before writing anything, and changes only the keys given.
"""
```

with:

```python
#!/usr/bin/env python3
"""Remembers which brd project the panel was last showing, and each project's
run settings.

    viewer-state.py get
    viewer-state.py set-project <root_path>
    viewer-state.py get-run-settings <root_path>
    viewer-state.py set-run-settings <root_path> <json>

State lives in ${XDG_STATE_HOME:-~/.local/state}/omarchy-project-manager/state.json
(reads fall back to the old brd-viewer/state.json until a new one is written). QML
cannot write files, hence this helper. Prints one JSON line. `get` and
`get-run-settings` never fail (a missing or corrupt file, or a damaged value, just
means the default); `set-project` and `set-run-settings` write atomically and keep
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

- [ ] **Step 6: Run the tests to verify they pass**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/projects/test_viewer_state.py tests/architecture -q`
Expected: all pass, 0 failed.

Check that both files are ASCII. Run: `LC_ALL=C grep -nP '[^\x00-\x7F]' core/backend/projects/viewer-state.py tests/core/backend/projects/test_viewer_state.py; echo "exit $?"`
Expected: no matches, `exit 1`.

Check that only the two files changed. Run: `git status --short`
Expected: ` M core/backend/projects/viewer-state.py` and ` M tests/core/backend/projects/test_viewer_state.py` only.

Run the full suite. Run: `bash tests/run.sh`
Expected: pytest reports 0 failed, every QML test prints `Totals: ... 0 failed`, and the script exits 0.

- [ ] **Step 7: Commit**

```bash
git add core/backend/projects/viewer-state.py tests/core/backend/projects/test_viewer_state.py
git commit -m "viewer-state.py: set-run-settings validates prefixHistory, parallelism and confirmDispatch by their own rules (S3 2.3)"
```

---

## Self-Review

1. **Spec coverage.**
   - Settings table and defaults: Task 1 (`RUN_SETTINGS_DEFAULTS`, `DEFAULTS`).
   - Get coercion per key, 2.2 entries and damaged files: Task 1 tests 1-4, plus the existing `treats_bad_files_as_defaults`, which now uses the six-key `DEFAULTS`.
   - Set per-key validation, exact sentences, input-order reporting, verbatim storage, wholesale replace, no parallelism cap, other keys preserved, per root: Task 2 tests 5-14.
   - Refusals 15-18: the `BAD_UPDATES` additions.
   - Docstring: Task 2 Step 5.
   - Existing-test edits are limited to the ones the spec lists.
   - Out-of-scope files are untouched (Global Constraints, plus the `git status` check).
2. **Placeholder scan.** Every code step shows full code. There is no TBD and no "similar to".
3. **Type consistency.** These names are the same in Task 1 (produced) and Task 2 (consumed): `PREFIX_HISTORY_CAP`, `RUN_SETTINGS_DEFAULTS`, `RUN_SETTINGS_VALID`, `valid_prefix_history`, `valid_parallelism`, `valid_boolean`, `RUN_SETTINGS_REFUSALS`. The test helper `same_json` is defined in Task 2 before its first use. Task 1 tests do not use it.
4. **Review Focus.** Each of the five lines has a named test in its owning task: strict JSON and every field damaged in Task 1; set-project interleaving, huge values and the two extra `BAD_UPDATES` rows in Task 2.
<!-- task-pipeline: validated -->
