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
