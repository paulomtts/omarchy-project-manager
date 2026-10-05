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
