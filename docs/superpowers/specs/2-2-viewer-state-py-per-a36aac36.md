# 2.2 viewer-state.py: per-project run settings (card a36aac36)

Narrowed from `docs/superpowers/specs/2026-10-03-am-run-controls-design.md` (S2):
"Control actions", the verify-set fact (lines 49-53), "Alerts" item 2 (lines
119-123) and "Open questions" bullet 2 (lines 168-170). Parent story 90acc3d7.
Blocked by b661b0a4 (2.1 `run-control.py`), which is on this branch; nothing in
it is touched.

The storage question the parent leaves open ("decided in S3", lines 168-170) is
settled by this card and by
`docs/superpowers/specs/2026-10-03-am-run-dispatch-design.md` lines 113-117: the
settings live in `viewer-state.py` as `get-run-settings` / `set-run-settings`,
and S3 adds fields to that same store rather than creating a second one.

## Starting point

- `core/backend/projects/viewer-state.py` (75 lines) has `get` and
  `set-project <root_path>`. State is one JSON object in
  `${XDG_STATE_HOME:-~/.local/state}/omarchy-project-manager/state.json`;
  `load()` reads it, falling back to the legacy `brd-viewer/state.json` while the
  new file is absent, and returns `{}` for a missing, unreadable, non-JSON or
  non-object file. `cmd_set_project` loads, mutates one key, `makedirs`, and
  writes with `write_atomic(path, ..., mode=0o600)`; an `OSError` prints
  `{"ok": false, "error": "<text>"}` and exits 1. Bad usage prints
  `{"ok": false, "error": "usage: ..."}` and exits 2.
- `write_atomic` (`core/backend/common/atomic_write.py`) and `emit`
  (`core/backend/common/json_line.py`) must be imported, never redefined
  (`docs/architecture.md` lines 174-180; `tests/architecture/test_layers.py`
  `DUPLICATED_PY`). Backend code imports only the stdlib and `common`.
- `tests/core/backend/projects/test_viewer_state.py` runs the script as a
  subprocess with a throwaway `HOME` and `XDG_STATE_HOME` (`env` fixture,
  `run(env, *args) -> (code, last JSON line)`, `state_file(env)`).

## Scope

`core/backend/projects/viewer-state.py` (two new subcommands, the usage string
and the module docstring) and `tests/core/backend/projects/test_viewer_state.py`
(new tests appended; existing tests unchanged and still passing). Tests first.

### Out of scope

- Any caller: `RunStore.qml` reading the stored verify set for Resume (parent
  lines 49-53, 65-69), the Resume confirm step and its "no verification"
  opt-out UI, the RunStore card.
- `core/backend/runs/notify.py`, `notify-send`, toasts and anything that acts on
  `notifyOnEscalation` (parent lines 119-123, 135-136): their own cards. This
  card only stores the flag.
- S3's dispatch fields (prefix history, parallelism, "Confirm dispatches";
  dispatch spec lines 76-85, 113-117): S3 adds them to this store later.
- `run-control.py` (card 2.1) and every other helper: unchanged.
- `docs/architecture.md`: left for S2's docs card.
- The stray third blank line after the imports (viewer-state.py lines 20-22):
  not touched.

## Behaviour

### Settings and defaults

Per project root, three settings:

| key | type | default | meaning |
|---|---|---|---|
| `verify` | list of non-empty strings | `[]` | the verify commands last used for this project, in order; each is one `--verify` value |
| `allowNoVerification` | boolean | `false` | the explicit "no verification" opt-out (`--allow-no-verification`) |
| `notifyOnEscalation` | boolean | `false` | desktop alert on escalation; **off by default** (parent line 119) |

The parent spec calls "Notify on escalation" a per-viewer setting (line 119-120);
the card stores it per project root, and this spec follows the card.

### Storage

Settings are stored in the existing `state.json` under the top-level key
`run_settings`, an object keyed by project root:

```json
{"last_project": "/home/u/p",
 "run_settings": {"/home/u/p": {"verify": ["uv run pytest"],
                                 "allowNoVerification": false,
                                 "notifyOnEscalation": true}}}
```

- The root is used as the key **verbatim** (no normalisation: `/p` and `/p/` are
  different projects). Callers pass the same root string `set-project` gets.
- Every other top-level key (`last_project`, anything unknown) and every other
  root's entry is preserved by `set-run-settings`; `set-project` likewise keeps
  `run_settings` (it already preserves unknown keys).
- Keys inside a root's entry that this version does not know (written by a newer
  version) are preserved by `set-run-settings`.

### `get-run-settings <root_path>`

Prints exactly one JSON line and **always exits 0** (like `get`):

```json
{"verify": [...], "allowNoVerification": false, "notifyOnEscalation": false}
```

Exactly these three keys, always present, never anything else (unknown stored
keys are not echoed). Each key is resolved independently:

- No file, unreadable file, non-JSON, non-object file, `run_settings` missing or
  not an object, no entry for the root, or an entry that is not an object: all
  three defaults.
- `verify`: the stored value if it is a list whose every element is a non-empty
  string (an element that is empty or only whitespace makes it invalid);
  otherwise `[]`. A partially valid list is **not** filtered: the whole value
  falls back to `[]`, so a damaged set is never silently run in part.
- `allowNoVerification`, `notifyOnEscalation`: the stored value only if it is a
  JSON boolean (`0`, `1`, `"true"`, `null` are not); otherwise the default.
- Reads the legacy file when the new one is absent, exactly as `get` does.

### `set-run-settings <root_path> <json>`

`<json>` is one argument holding a JSON object with any subset of the three keys
(a **partial update**):

- Given keys replace the stored values for that root; keys not given keep their
  stored values (stored values are not validated or rewritten on the way
  through; `get-run-settings` coerces them on read). `{}` is valid: it writes the
  file, creating an empty entry for the root if none existed.
- Validation happens before anything is written; any failure prints
  `{"ok": false, "error": "<one sentence naming the problem>"}`, exits **2**, and
  leaves the state file byte-for-byte unchanged (or absent). Failures:
  - not valid JSON;
  - valid JSON but not an object (list, string, number, `null`);
  - an unknown key (e.g. `allow_no_verification`; typos are rejected rather than
    stored). The error names the key. S3 extends the known-key list;
  - `verify` not a list, or containing an element that is not a string, or a
    string that is empty or only whitespace;
  - `allowNoVerification` or `notifyOnEscalation` not a JSON boolean.
- Accepted strings are stored exactly as given (no trimming, order and duplicates
  kept); non-ASCII round-trips.
- Writes like `set-project`: `load()` (so legacy content is carried forward and a
  corrupt file is replaced by a fresh object, as today), `makedirs`,
  `write_atomic(..., mode=0o600)`; no temp files left behind; a new file is
  `0o600`, an existing file keeps its mode.
- Success: `{"ok": true}`, exit 0. `OSError` while writing:
  `{"ok": false, "error": "<text>"}`, exit 1.

### Command line and usage

- `get-run-settings` takes exactly one argument; `set-run-settings` exactly two.
  `<root_path>` must be non-empty. Any other shape (missing or extra arguments,
  empty root, unknown subcommand) prints
  `{"ok": false, "error": USAGE}` and exits 2, writing nothing, where USAGE is
  exactly
  `usage: viewer-state.py get | set-project <root_path> | get-run-settings <root_path> | set-run-settings <root_path> <json>`.
- `get` and `set-project` behave exactly as today (their usage cases keep
  exiting 2 with the new string).
- The module docstring lists all four commands and states that
  `get-run-settings` never fails and `set-run-settings` validates, writes
  atomically and keeps other keys.
- The file stays ASCII.

## Tests (appended to `tests/core/backend/projects/test_viewer_state.py`)

Tier: **backend pytest, subprocess** (parent "Testing" bullet 3, lines 155-156;
`docs/architecture.md` "How to add: A helper script"). The helper's contract is
argv in, one JSON line, an exit code and a file on disk out; no Qt, no `am`, so
the existing `env`/`run`/`state_file` harness exercises it end to end against a
throwaway state dir. `DEFAULTS = {"verify": [], "allowNoVerification": False,
"notifyOnEscalation": False}`.

Get:
1. `test_get_run_settings_with_no_file_is_defaults` — `(0, DEFAULTS)`.
2. `test_get_run_settings_treats_bad_files_as_defaults` — parametrised file
   content: `""`, `"not json"`, `"[1]"`, `'{"run_settings": 5}'`,
   `'{"run_settings": {"/p": "x"}}'`, `'{"run_settings": {"/other": {"notifyOnEscalation": true}}}'`:
   `(0, DEFAULTS)` for root `/p`.
3. `test_get_run_settings_coerces_each_bad_field_independently` — parametrised
   stored entries: `verify` = `"pytest"`, `["a", 5]`, `["a", ""]`, `["  "]`,
   `null`; `allowNoVerification` = `1`, `"true"`, `null`; `notifyOnEscalation` =
   `0`, `"yes"`: the bad field reads as its default while a valid sibling field
   stored alongside it (e.g. `notifyOnEscalation: true`) is still returned.
4. `test_get_run_settings_returns_only_known_keys` — an entry with an extra
   `"future": 1` reads back without it.
5. `test_get_run_settings_reads_the_legacy_file` — legacy `brd-viewer/state.json`
   with an entry, no new file: returned.

Set:
6. `test_set_then_get_run_settings_round_trips` — full object with
   `verify: ["uv run pytest", "npm test -- --ci"]` and both booleans `true`:
   `(0, {"ok": True})`, then get returns it exactly, order kept.
7. `test_set_run_settings_is_partial` — set `{"verify": ["a"]}`, then
   `{"notifyOnEscalation": true}`: get gives `verify ["a"]`,
   `notifyOnEscalation true`, `allowNoVerification false`; then `{"verify": []}`
   clears the list and keeps the flag.
8. `test_set_run_settings_empty_object_is_accepted` — `{}` exit 0; get is
   `DEFAULTS`; file exists with `run_settings["/p"] == {}`.
9. `test_run_settings_are_per_root` — different values for `/a` and `/b`
   (including a root with spaces); each reads its own; an unknown root reads
   `DEFAULTS`; `/a/` reads `DEFAULTS` (verbatim keys).
10. `test_set_run_settings_preserves_other_keys` — file with `last_project`,
    `other: {"x": 1}`, another root's entry and an unknown key inside this
    root's entry: after set, all still present and unchanged, only the given key
    changed.
11. `test_set_project_preserves_run_settings` — set-run-settings, then
    set-project: get-run-settings unchanged, `get` returns the project.
12. `test_set_run_settings_keeps_strings_verbatim` — `verify` with leading/
    trailing spaces, shell metacharacters (`;`, `$(x)`, `&&`), a duplicate entry
    and a non-ASCII command: read back identical.
13. `test_set_run_settings_rejects_bad_json` — parametrised `<json>`: `""`,
    `"{"`, `"[]"`, `'"x"'`, `"null"`, `"5"`, `'{"allow_no_verification": true}'`,
    `'{"verify": "pytest"}'`, `'{"verify": [1]}'`, `'{"verify": [""]}'`,
    `'{"verify": ["  "]}'`, `'{"allowNoVerification": "true"}'`,
    `'{"notifyOnEscalation": 1}'`, `'{"notifyOnEscalation": null}'`: exit 2,
    `ok` false, non-empty `error`; with a pre-existing state file its bytes are
    unchanged; with none, no file is created.
14. `test_unknown_key_error_names_the_key` — `{"verfy": []}`: error contains
    `verfy`.
15. `test_set_run_settings_leaves_no_temp_files_behind` — directory holds only
    `state.json`.
16. `test_new_state_file_from_run_settings_is_private` — mode `0o600`.
17. `test_set_run_settings_unwritable_directory_fails_cleanly` — skipped as root;
    dir `0o500`: exit 1, `ok` false, non-empty `error`.
18. `test_set_run_settings_carries_legacy_state_forward` — legacy file with
    `last_project` only: after set-run-settings the new file has both
    `last_project` and the settings; the legacy file is untouched.

Usage:
19. `test_run_settings_bad_usage_is_rejected` — parametrised: `("get-run-settings",)`,
    `("get-run-settings", "")`, `("get-run-settings", "/p", "x")`,
    `("set-run-settings",)`, `("set-run-settings", "/p")`,
    `("set-run-settings", "", "{}")`, `("set-run-settings", "/p", "{}", "x")`:
    exit 2, `error` exactly USAGE, no state file created.
20. The existing `test_bad_usage_is_rejected` keeps passing (it asserts only code
    and `ok`).

Architecture tier (existing, unchanged): `tests/architecture` stays green — no
redefinition of `emit`/`write_atomic`, stdlib-only imports, ASCII source.

Verification: `bash tests/run.sh` green.

## Review focus (inputs most likely to bite, for the planner)

1. A partial `set-run-settings` (e.g. only `notifyOnEscalation`) must not wipe a
   stored verify set: the Resume path depends on it surviving.
2. A rejected `set-run-settings` must not touch the file at all — validation
   strictly before `load`/write.
3. Hand-edited or damaged stored values (`verify: ["a", 5]`, `"true"` strings):
   `get-run-settings` must still exit 0 with all three keys, falling back per
   field.
4. `set-project` and `set-run-settings` interleaved must each keep the other's
   data (both go through the same load-mutate-write of one file).
5. Verify commands containing spaces, quotes, shell metacharacters or non-ASCII
   must round-trip as exact single strings.
