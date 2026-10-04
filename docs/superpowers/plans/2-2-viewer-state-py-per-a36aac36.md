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


---

# viewer-state.py run settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `core/backend/projects/viewer-state.py` two new subcommands, `get-run-settings <root_path>` and `set-run-settings <root_path> <json>`, that read and partially update per-project run settings (`verify`, `allowNoVerification`, `notifyOnEscalation`) stored under `run_settings` in the existing `state.json`. Write them test-first in `tests/core/backend/projects/test_viewer_state.py`.

**Architecture:** Everything stays in the one stdlib-only script. `get-run-settings` reuses `load()` and coerces each field on its own (`valid_verify`, `isinstance(value, bool)`), so it always exits 0. `set-run-settings` validates the argument first (`parse_run_settings` returns `(update, error)`), and only then runs `load()`, merges the update into `run_settings[root]`, and writes through a `save(data)` helper. That helper is factored out of `cmd_set_project` so both writers share one load-mutate-write path. There are two tasks: (1) the read side plus the new USAGE string, (2) the write side plus the final docstring.

**Tech Stack:** Python 3 stdlib (`json`, `os`, `sys`), `common.atomic_write.write_atomic`, `common.json_line.emit`, pytest running the script as a subprocess.

**Spec:** `docs/superpowers/specs/2-2-viewer-state-py-per-a36aac36.md` (prepended above). Parent design: `docs/superpowers/specs/2026-10-03-am-run-controls-design.md` (S2).

**Worktree / branch:** all paths are relative to `/home/mtts/Code/omarchy-project-manager/.claude/worktrees/ctl/task-2-2-viewer-state-py-per-a36aac36`, branch `ctl/task-2-2-viewer-state-py-per-a36aac36`. Run every command from that directory.

**Running pytest:** `python3` here is a uv-managed interpreter without pytest (see `tests/run.sh`), so every pytest command below is written as `uv run --with pytest python3 -m pytest ...`.

## Global Constraints

- USAGE is exactly `usage: viewer-state.py get | set-project <root_path> | get-run-settings <root_path> | set-run-settings <root_path> <json>`. Every bad command line prints `{"ok": false, "error": USAGE}`, exits 2 and writes nothing.
- `get-run-settings` takes exactly one non-empty argument and `set-run-settings` exactly two, with the first one non-empty.
- `get-run-settings` prints exactly `{"verify": [...], "allowNoVerification": <bool>, "notifyOnEscalation": <bool>}` and always exits 0.
- Defaults: `verify` `[]`, `allowNoVerification` `false`, `notifyOnEscalation` `false`.
- Storage: top-level key `run_settings`, an object keyed by the root path **verbatim**. Every other key at every level is preserved.
- `set-run-settings` validation errors print `{"ok": false, "error": "<one sentence>"}`, exit 2, and happen before `load()`. The file stays byte-for-byte unchanged, or absent.
- Success prints `{"ok": true}` and exits 0. An `OSError` while writing prints `{"ok": false, "error": str(e)}` and exits 1.
- Writes go through `os.makedirs(..., exist_ok=True)` + `write_atomic(path, ..., mode=0o600)`. `write_atomic` and `emit` are imported, never redefined (`tests/architecture/test_layers.py` `DUPLICATED_PY`). The script imports only the stdlib and `common`.
- `get` and `set-project` keep today's behaviour. The stray third blank line after the imports (`viewer-state.py` lines 20-22) is **not** touched.
- `viewer-state.py` and the test file stay ASCII. Non-ASCII in tests is written as `\uXXXX` escapes.
- Existing tests in `test_viewer_state.py` are not edited. New tests are appended at the end of the file.
- Do not touch `run-control.py`, `RunStore.qml`, `notify.py`, `docs/architecture.md` or any other file.
- Verification: `bash tests/run.sh` green.

## Review Focus

The spec's own five review-focus inputs are pinned by its numbered tests: a partial set by `test_set_run_settings_is_partial`, a rejected set leaving the file alone by `test_set_run_settings_rejection_leaves_the_file_untouched`, damaged stored values by `test_get_run_settings_coerces_each_bad_field_independently`, interleaving with set-project by `test_set_project_preserves_run_settings` / `test_set_run_settings_preserves_other_keys`, and verbatim strings by `test_set_run_settings_keeps_strings_verbatim`. The spec implies five more inputs that none of its numbered tests exercise. Each one has a test in the task that owns the code:

1. **A stored `run_settings` (or a root's entry) that is the wrong JSON type**, e.g. `5`, `[]`, `null`, `"x"`, after a hand edit or a bug. `set-run-settings` must replace it with an object and succeed, not crash with `AttributeError` (that would be a traceback, not one JSON line). Every other top-level key is kept. Pinned by `test_set_run_settings_repairs_a_damaged_settings_shape` (Task 2).
2. **A state file that is not JSON at all** when `set-run-settings` runs. The file is replaced by a fresh object holding just the new settings, as `set-project` already does. Pinned by `test_set_run_settings_replaces_a_corrupt_file` (Task 2).
3. **An update with one good key and one bad key**, e.g. `{"verify": ["a"], "bogus": 1}`. The whole update is rejected: the good half is not applied and the file is untouched. Pinned by the extra `BAD_UPDATES` entry in `test_set_run_settings_rejects_bad_json` / `test_set_run_settings_rejection_leaves_the_file_untouched` (Task 2).
4. **`get-run-settings` on a machine with no state yet.** A read must not create the state directory or file. Pinned by `test_get_run_settings_writes_nothing` (Task 1).
5. **A root path that looks like a flag (`-p`, `--help`) or holds non-ASCII.** It is just a root: it is stored and read back, and is not taken for a usage error. Pinned by `test_run_settings_root_is_any_non_empty_string` (Task 2).

The spec also says (Behaviour, set-run-settings) that stored values not given in an update "are not validated or rewritten on the way through". `test_set_run_settings_keeps_damaged_stored_fields_it_was_not_given` (Task 2) pins that.

## File Structure

- Modify: `core/backend/projects/viewer-state.py`. It gets the module docstring, `USAGE`, `RUN_SETTINGS_DEFAULTS`, `valid_verify`, `run_settings_entry`, `cmd_get_run_settings` (Task 1), and `parse_run_settings`, `save`, `cmd_set_run_settings` (Task 2). `main` gets two new branches.
- Modify: `tests/core/backend/projects/test_viewer_state.py`. New constants, the helper `write_state` and the new tests are appended after the last existing test (`test_a_newly_created_state_file_is_private`, line 108-110).

No other file changes.

---

### Task 1: `get-run-settings` and the new USAGE string

**Files:**
- Modify: `core/backend/projects/viewer-state.py:2-11` (docstring), `:23` (insert constants above `state_base`), `:52` (insert functions after `cmd_get`), `:66-71` (`main`)
- Test: `tests/core/backend/projects/test_viewer_state.py` (append after line 110)

**Interfaces:**
- Consumes: the existing `load() -> dict` (it returns `{}` for a missing, unreadable, non-JSON or non-object file, and falls back to the legacy path), `emit(payload, code) -> int`, and the test harness `env` fixture, `run(env, *args) -> (int, dict | None)` and `state_file(env) -> Path`.
- Produces (used by Task 2):
  - `USAGE: str`, the exact usage string from Global Constraints.
  - `RUN_SETTINGS_DEFAULTS = {"verify": [], "allowNoVerification": False, "notifyOnEscalation": False}`. Its keys are also the set of known keys.
  - `valid_verify(value) -> bool`: True iff `value` is a list whose every element is a `str` with non-whitespace content.
  - `run_settings_entry(data: dict, root_path: str) -> dict`: the root's stored entry, or `{}` when `run_settings` or the entry is not an object.
  - `cmd_get_run_settings(root_path: str) -> int`.
  - Tests: `USAGE`, `DEFAULTS`, `write_state(env, content)` (a `str` is written verbatim, anything else as `json.dumps`).

- [ ] **Step 1: Write the failing tests**

Append to the end of `tests/core/backend/projects/test_viewer_state.py`. Keep the file's existing two-blank-line spacing: put two blank lines before `USAGE = ...`.

```python


# --- run settings ----------------------------------------------------------------

USAGE = ("usage: viewer-state.py get | set-project <root_path> | get-run-settings <root_path>"
         " | set-run-settings <root_path> <json>")
DEFAULTS = {"verify": [], "allowNoVerification": False, "notifyOnEscalation": False}


def write_state(env, content):
    """Writes the state file: a str verbatim, anything else as JSON."""
    state_file(env).parent.mkdir(parents=True, exist_ok=True)
    state_file(env).write_text(content if isinstance(content, str) else json.dumps(content))


def test_get_run_settings_with_no_file_is_defaults(env):
    assert run(env, "get-run-settings", "/p") == (0, DEFAULTS)


def test_get_run_settings_writes_nothing(env):
    run(env, "get-run-settings", "/p")
    assert not Path(env["XDG_STATE_HOME"]).exists()


@pytest.mark.parametrize("content", ["", "not json", "[1]", '{"run_settings": 5}', '{"run_settings": {"/p": "x"}}',
                                     '{"run_settings": {"/other": {"notifyOnEscalation": true}}}'])
def test_get_run_settings_treats_bad_files_as_defaults(env, content):
    write_state(env, content)
    assert run(env, "get-run-settings", "/p") == (0, DEFAULTS)


# Compared as JSON text: in Python 1 == True and 0 == False, so a dict compare
# would not notice a stored 1 or 0 leaking through as a "boolean".
@pytest.mark.parametrize("entry, expected", [
    ({"verify": "pytest", "notifyOnEscalation": True}, {**DEFAULTS, "notifyOnEscalation": True}),
    ({"verify": ["a", 5], "notifyOnEscalation": True}, {**DEFAULTS, "notifyOnEscalation": True}),
    ({"verify": ["a", ""], "notifyOnEscalation": True}, {**DEFAULTS, "notifyOnEscalation": True}),
    ({"verify": ["  "], "notifyOnEscalation": True}, {**DEFAULTS, "notifyOnEscalation": True}),
    ({"verify": None, "notifyOnEscalation": True}, {**DEFAULTS, "notifyOnEscalation": True}),
    ({"allowNoVerification": 1, "verify": ["a"]}, {**DEFAULTS, "verify": ["a"]}),
    ({"allowNoVerification": "true", "verify": ["a"]}, {**DEFAULTS, "verify": ["a"]}),
    ({"allowNoVerification": None, "verify": ["a"]}, {**DEFAULTS, "verify": ["a"]}),
    ({"notifyOnEscalation": 0, "allowNoVerification": True}, {**DEFAULTS, "allowNoVerification": True}),
    ({"notifyOnEscalation": "yes", "allowNoVerification": True}, {**DEFAULTS, "allowNoVerification": True}),
])
def test_get_run_settings_coerces_each_bad_field_independently(env, entry, expected):
    write_state(env, {"run_settings": {"/p": entry}})
    code, result = run(env, "get-run-settings", "/p")
    assert code == 0 and json.dumps(result, sort_keys=True) == json.dumps(expected, sort_keys=True)


def test_get_run_settings_returns_only_known_keys(env):
    write_state(env, {"run_settings": {"/p": {"verify": ["a"], "future": 1}}})
    assert run(env, "get-run-settings", "/p") == (0, {**DEFAULTS, "verify": ["a"]})


def test_get_run_settings_reads_the_legacy_file(env):
    old = Path(env["XDG_STATE_HOME"]) / "brd-viewer" / "state.json"
    old.parent.mkdir(parents=True)
    old.write_text(json.dumps({"run_settings": {"/p": {"verify": ["make check"], "allowNoVerification": True}}}))
    assert run(env, "get-run-settings", "/p") == (
        0, {"verify": ["make check"], "allowNoVerification": True, "notifyOnEscalation": False})


@pytest.mark.parametrize("args", [
    ("get-run-settings",), ("get-run-settings", ""), ("get-run-settings", "/p", "x"),
    ("set-run-settings",), ("set-run-settings", "/p"), ("set-run-settings", "", "{}"),
    ("set-run-settings", "/p", "{}", "x"),
])
def test_run_settings_bad_usage_is_rejected(env, args):
    assert run(env, *args) == (2, {"ok": False, "error": USAGE})
    assert not Path(env["XDG_STATE_HOME"]).exists()
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/projects/test_viewer_state.py -q`
Expected: 26 failed, 21 passed. Every new `get-run-settings` test fails with `assert (2, {...'usage: viewer-state.py get | set-project <root_path>'}) == (0, ...)`. Every `test_run_settings_bad_usage_is_rejected` case fails because `error` is the old usage string. The 20 existing tests and `test_get_run_settings_writes_nothing` pass: the old script already writes nothing on a usage error, and that test exists to guard the new code.

- [ ] **Step 3: Write the minimal implementation**

In `core/backend/projects/viewer-state.py`, replace the docstring (lines 2-12):

```python
"""Remembers which brd project the panel was last showing, and each project's
run settings.

    viewer-state.py get
    viewer-state.py set-project <root_path>
    viewer-state.py get-run-settings <root_path>

State lives in ${XDG_STATE_HOME:-~/.local/state}/omarchy-project-manager/state.json
(reads fall back to the old brd-viewer/state.json until a new one is written). QML
cannot write files, hence this helper. Prints one JSON line. `get` and
`get-run-settings` never fail (a missing or corrupt file, or a damaged value, just
means the default); `set-project` writes atomically and keeps any other keys
already in the file.
"""
```

Leave lines 13-22 exactly as they are, including the three blank lines after the imports. Then, directly above `def state_base():`, insert:

```python
USAGE = ("usage: viewer-state.py get | set-project <root_path> | get-run-settings <root_path>"
         " | set-run-settings <root_path> <json>")
RUN_SETTINGS_DEFAULTS = {"verify": [], "allowNoVerification": False, "notifyOnEscalation": False}


```

(That is the two constants, then two blank lines, then `def state_base():`.)

After `cmd_get` (after its `return emit(...)` line, before `def cmd_set_project`), insert:

```python
def valid_verify(value):
    return isinstance(value, list) and all(isinstance(v, str) and v.strip() for v in value)


def run_settings_entry(data, root_path):
    settings = data.get("run_settings")
    entry = settings.get(root_path) if isinstance(settings, dict) else None
    return entry if isinstance(entry, dict) else {}


def cmd_get_run_settings(root_path):
    entry = run_settings_entry(load(), root_path)
    verify = entry.get("verify")
    result = {"verify": verify if valid_verify(verify) else []}
    for key in ("allowNoVerification", "notifyOnEscalation"):
        value = entry.get(key)
        result[key] = value if isinstance(value, bool) else RUN_SETTINGS_DEFAULTS[key]
    return emit(result, 0)


```

Replace `main` with:

```python
def main(argv):
    if argv[:1] == ["get"] and len(argv) == 1:
        return cmd_get()
    if argv[:1] == ["set-project"] and len(argv) == 2 and argv[1]:
        return cmd_set_project(argv[1])
    if argv[:1] == ["get-run-settings"] and len(argv) == 2 and argv[1]:
        return cmd_get_run_settings(argv[1])
    return emit({"ok": False, "error": USAGE}, 2)
```

Notes for the implementer:
- `isinstance(value, bool)` is the whole boolean check. In JSON, `0`/`1` load as `int`, which is not `bool`.
- `valid_verify` rejects the whole list if any one element is bad. Never filter the list: the spec says a damaged set must not be run in part.
- `result["verify"]` is a fresh `[]` literal, never `RUN_SETTINGS_DEFAULTS["verify"]`, so the shared default is never handed out.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/projects/test_viewer_state.py tests/architecture -q`
Expected: all pass (47 in `test_viewer_state.py`, plus the architecture tests), 0 failed.

- [ ] **Step 5: Commit**

```bash
git add core/backend/projects/viewer-state.py tests/core/backend/projects/test_viewer_state.py
git commit -m "feat(projects): viewer-state.py get-run-settings reads a project's run settings with per-field defaults (card a36aac36)"
```

---

### Task 2: `set-run-settings` (validated partial update) and the final docstring

**Files:**
- Modify: `core/backend/projects/viewer-state.py`: the docstring, a new `parse_run_settings` after `cmd_get_run_settings`, `cmd_set_project` (its write moves into `save`), a new `cmd_set_run_settings` after `cmd_set_project`, and `main`
- Test: `tests/core/backend/projects/test_viewer_state.py` (append after the Task 1 tests)

**Interfaces:**
- Consumes (from Task 1): `USAGE`, `RUN_SETTINGS_DEFAULTS`, `valid_verify(value) -> bool`, `cmd_get_run_settings`, and from the tests `DEFAULTS` and `write_state(env, content)`. From the original file: `load() -> dict`, `state_path() -> str`, `write_atomic`, `emit`.
- Produces:
  - `parse_run_settings(text: str) -> tuple[dict | None, str | None]`: `(update, None)` when valid, `(None, "<sentence>")` otherwise.
  - `save(data: dict) -> int`: `makedirs` + `write_atomic(..., mode=0o600)`. It emits `{"ok": true}` and returns 0, or, on `OSError`, emits `{"ok": false, "error": str(e)}` and returns 1.
  - `cmd_set_run_settings(root_path: str, text: str) -> int`.

- [ ] **Step 1: Write the failing tests**

Append to the end of `tests/core/backend/projects/test_viewer_state.py`:

```python


def test_set_then_get_run_settings_round_trips(env):
    settings = {"verify": ["uv run pytest", "npm test -- --ci"], "allowNoVerification": True, "notifyOnEscalation": True}
    assert run(env, "set-run-settings", "/p", json.dumps(settings)) == (0, {"ok": True})
    assert run(env, "get-run-settings", "/p") == (0, settings)


def test_set_run_settings_is_partial(env):
    assert run(env, "set-run-settings", "/p", '{"verify": ["a"]}') == (0, {"ok": True})
    assert run(env, "set-run-settings", "/p", '{"notifyOnEscalation": true}') == (0, {"ok": True})
    assert run(env, "get-run-settings", "/p") == (
        0, {"verify": ["a"], "allowNoVerification": False, "notifyOnEscalation": True})
    assert run(env, "set-run-settings", "/p", '{"verify": []}') == (0, {"ok": True})
    assert run(env, "get-run-settings", "/p") == (
        0, {"verify": [], "allowNoVerification": False, "notifyOnEscalation": True})


def test_set_run_settings_empty_object_is_accepted(env):
    assert run(env, "set-run-settings", "/p", "{}") == (0, {"ok": True})
    assert run(env, "get-run-settings", "/p") == (0, DEFAULTS)
    assert json.loads(state_file(env).read_text())["run_settings"]["/p"] == {}


def test_run_settings_are_per_root(env):
    assert run(env, "set-run-settings", "/a", '{"verify": ["make a"], "notifyOnEscalation": true}')[0] == 0
    assert run(env, "set-run-settings", "/home/u/my proj", '{"verify": ["make b"], "allowNoVerification": true}')[0] == 0
    assert run(env, "get-run-settings", "/a") == (
        0, {"verify": ["make a"], "allowNoVerification": False, "notifyOnEscalation": True})
    assert run(env, "get-run-settings", "/home/u/my proj") == (
        0, {"verify": ["make b"], "allowNoVerification": True, "notifyOnEscalation": False})
    assert run(env, "get-run-settings", "/c") == (0, DEFAULTS)
    assert run(env, "get-run-settings", "/a/") == (0, DEFAULTS)


def test_set_run_settings_preserves_other_keys(env):
    write_state(env, {"last_project": "/p", "other": {"x": 1},
                      "run_settings": {"/q": {"verify": ["q"]}, "/p": {"verify": ["old"], "future": 1}}})
    assert run(env, "set-run-settings", "/p", '{"notifyOnEscalation": true}') == (0, {"ok": True})
    assert json.loads(state_file(env).read_text()) == {
        "last_project": "/p", "other": {"x": 1},
        "run_settings": {"/q": {"verify": ["q"]},
                         "/p": {"verify": ["old"], "future": 1, "notifyOnEscalation": True}}}


def test_set_project_preserves_run_settings(env):
    stored = {"verify": ["a"], "allowNoVerification": False, "notifyOnEscalation": True}
    assert run(env, "set-run-settings", "/p", json.dumps(stored)) == (0, {"ok": True})
    assert run(env, "set-project", "/p") == (0, {"ok": True})
    assert run(env, "get-run-settings", "/p") == (0, stored)
    assert run(env, "get") == (0, {"last_project": "/p"})
    assert run(env, "set-run-settings", "/p", '{"allowNoVerification": true}') == (0, {"ok": True})
    assert run(env, "get") == (0, {"last_project": "/p"})


def test_set_run_settings_keeps_strings_verbatim(env):
    verify = ["  uv run pytest  ", "make a; make b", "echo $(x) && true", "make a; make b",
              "pytest -k 'caf\u00e9'", 'say "hi" \u65e5\u672c']
    assert run(env, "set-run-settings", "/p", json.dumps({"verify": verify}, ensure_ascii=False)) == (0, {"ok": True})
    assert run(env, "get-run-settings", "/p")[1]["verify"] == verify


BAD_UPDATES = ["", "{", "[]", '"x"', "null", "5", '{"allow_no_verification": true}', '{"verify": "pytest"}',
               '{"verify": [1]}', '{"verify": [""]}', '{"verify": ["  "]}', '{"allowNoVerification": "true"}',
               '{"notifyOnEscalation": 1}', '{"notifyOnEscalation": null}', '{"verify": ["a"], "bogus": 1}']


@pytest.mark.parametrize("update", BAD_UPDATES)
def test_set_run_settings_rejects_bad_json(env, update):
    code, result = run(env, "set-run-settings", "/p", update)
    assert code == 2 and result["ok"] is False and result["error"]
    assert not Path(env["XDG_STATE_HOME"]).exists()


@pytest.mark.parametrize("update", BAD_UPDATES)
def test_set_run_settings_rejection_leaves_the_file_untouched(env, update):
    write_state(env, {"last_project": "/p", "run_settings": {"/p": {"verify": ["a"]}}})
    before = state_file(env).read_bytes()
    code, result = run(env, "set-run-settings", "/p", update)
    assert code == 2 and result["ok"] is False and result["error"]
    assert state_file(env).read_bytes() == before
    assert [p.name for p in state_file(env).parent.iterdir()] == ["state.json"]


def test_unknown_key_error_names_the_key(env):
    code, result = run(env, "set-run-settings", "/p", '{"verfy": []}')
    assert code == 2 and "verfy" in result["error"]


def test_set_run_settings_leaves_no_temp_files_behind(env):
    run(env, "set-run-settings", "/p", '{"verify": ["a"]}')
    assert [p.name for p in state_file(env).parent.iterdir()] == ["state.json"]


def test_new_state_file_from_run_settings_is_private(env):
    run(env, "set-run-settings", "/p", "{}")
    assert (state_file(env).stat().st_mode & 0o777) == 0o600


@pytest.mark.skipif(os.geteuid() == 0, reason="root ignores directory permissions")
def test_set_run_settings_unwritable_directory_fails_cleanly(env):
    d = state_file(env).parent
    d.mkdir(parents=True)
    d.chmod(0o500)
    try:
        code, result = run(env, "set-run-settings", "/p", '{"verify": ["a"]}')
    finally:
        d.chmod(0o700)
    assert code == 1 and result["ok"] is False and result["error"]


def test_set_run_settings_carries_legacy_state_forward(env):
    old = Path(env["XDG_STATE_HOME"]) / "brd-viewer" / "state.json"
    old.parent.mkdir(parents=True)
    old.write_text('{"last_project": "/home/u/old"}')
    assert run(env, "set-run-settings", "/p", '{"verify": ["a"]}') == (0, {"ok": True})
    assert json.loads(state_file(env).read_text()) == {
        "last_project": "/home/u/old", "run_settings": {"/p": {"verify": ["a"]}}}
    assert old.read_text() == '{"last_project": "/home/u/old"}'


def test_set_run_settings_replaces_a_corrupt_file(env):
    write_state(env, "not json")
    assert run(env, "set-run-settings", "/p", '{"notifyOnEscalation": true}') == (0, {"ok": True})
    assert json.loads(state_file(env).read_text()) == {"run_settings": {"/p": {"notifyOnEscalation": True}}}


@pytest.mark.parametrize("stored", [5, "x", [], None, {"/p": "x"}, {"/p": ["a"]}, {"/p": None}])
def test_set_run_settings_repairs_a_damaged_settings_shape(env, stored):
    write_state(env, {"last_project": "/p", "run_settings": stored})
    assert run(env, "set-run-settings", "/p", '{"verify": ["a"]}') == (0, {"ok": True})
    data = json.loads(state_file(env).read_text())
    assert data["last_project"] == "/p" and data["run_settings"]["/p"] == {"verify": ["a"]}
    assert run(env, "get-run-settings", "/p") == (0, {**DEFAULTS, "verify": ["a"]})


def test_set_run_settings_keeps_damaged_stored_fields_it_was_not_given(env):
    write_state(env, {"run_settings": {"/p": {"verify": ["a", 5]}}})
    assert run(env, "set-run-settings", "/p", '{"notifyOnEscalation": true}') == (0, {"ok": True})
    assert json.loads(state_file(env).read_text())["run_settings"]["/p"] == {
        "verify": ["a", 5], "notifyOnEscalation": True}
    assert run(env, "get-run-settings", "/p") == (0, {**DEFAULTS, "notifyOnEscalation": True})


@pytest.mark.parametrize("root", ["-p", "--help", "/home/u/caf\u00e9"])
def test_run_settings_root_is_any_non_empty_string(env, root):
    assert run(env, "set-run-settings", root, '{"verify": ["a"]}') == (0, {"ok": True})
    assert run(env, "get-run-settings", root) == (0, {**DEFAULTS, "verify": ["a"]})
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/projects/test_viewer_state.py -q`
Expected: 24 failed, 77 passed. Every success-path test fails with `assert (2, {'ok': False, 'error': 'usage: ...'}) == (0, {'ok': True})`. The temp-file and mode tests fail with `FileNotFoundError`, because nothing was written. The unwritable-directory test fails with `assert 2 == 1`. `test_unknown_key_error_names_the_key` fails with `assert ('verfy' in 'usage: ...')`. Both `BAD_UPDATES` tests (30 cases) pass, because the old script already rejects with exit 2 and writes nothing. They are there to guard the new code.

- [ ] **Step 3: Write the minimal implementation**

In `core/backend/projects/viewer-state.py`, replace the docstring with the final one:

```python
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

After `cmd_get_run_settings` (before `def cmd_set_project`), insert:

```python
def parse_run_settings(text):
    """The update in `text` and None, or None and a sentence saying what is wrong."""
    try:
        update = json.loads(text)
    except ValueError:
        return None, "The run settings are not valid JSON."
    if not isinstance(update, dict):
        return None, "The run settings must be a JSON object."
    for key, value in update.items():
        if key not in RUN_SETTINGS_DEFAULTS:
            return None, "Unknown run setting: %s." % key
        if key == "verify" and not valid_verify(value):
            return None, "verify must be a list of non-empty strings."
        if key != "verify" and not isinstance(value, bool):
            return None, "%s must be true or false." % key
    return update, None


```

Replace `cmd_set_project` (the whole function) with `save` plus the slimmed `cmd_set_project` and the new `cmd_set_run_settings`:

```python
def save(data):
    path = state_path()
    directory = os.path.dirname(path)
    try:
        os.makedirs(directory, exist_ok=True)
        write_atomic(path, json.dumps(data).encode("utf-8"), mode=0o600)
    except OSError as e:
        return emit({"ok": False, "error": str(e)}, 1)
    return emit({"ok": True}, 0)


def cmd_set_project(root_path):
    data = load()
    data["last_project"] = root_path
    return save(data)


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

Replace `main` with:

```python
def main(argv):
    if argv[:1] == ["get"] and len(argv) == 1:
        return cmd_get()
    if argv[:1] == ["set-project"] and len(argv) == 2 and argv[1]:
        return cmd_set_project(argv[1])
    if argv[:1] == ["get-run-settings"] and len(argv) == 2 and argv[1]:
        return cmd_get_run_settings(argv[1])
    if argv[:1] == ["set-run-settings"] and len(argv) == 3 and argv[1]:
        return cmd_set_run_settings(argv[1], argv[2])
    return emit({"ok": False, "error": USAGE}, 2)
```

Notes for the implementer:
- `parse_run_settings` runs before `load()`. That ordering is what keeps a rejected update from touching the file. Do not move the `load()` call above it.
- `json.loads("")` raises `json.JSONDecodeError`, which is a `ValueError`, so the empty argument is covered by the same `except`.
- An update with a valid key and a bad key returns the error before anything is merged, so nothing is applied.
- `entry.update(update)` replaces only the given keys. It leaves unknown and damaged stored keys exactly as they were (the spec: stored values "are not validated or rewritten on the way through").
- `json.dumps` keeps its default `ensure_ascii=True`, so non-ASCII is written as `\uXXXX`. It still round-trips, and the file stays ASCII.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/projects/test_viewer_state.py tests/architecture -q`
Expected: all pass (101 in `test_viewer_state.py`, plus the architecture tests), 0 failed. Then check the script is ASCII. Run: `LC_ALL=C grep -nP '[^\x00-\x7F]' core/backend/projects/viewer-state.py tests/core/backend/projects/test_viewer_state.py; echo "exit $?"`. Expected: no matches, `exit 1`.

Then run the full suite. Run: `bash tests/run.sh`. Expected: pytest reports 0 failed, every QML test prints `Totals: ... 0 failed`, and the script exits 0.

- [ ] **Step 5: Commit**

```bash
git add core/backend/projects/viewer-state.py tests/core/backend/projects/test_viewer_state.py
git commit -m "feat(projects): viewer-state.py set-run-settings validates and partially updates a project's run settings (card a36aac36)"
```

---

## Self-Review

**Spec coverage.**
- Settings table and defaults: Task 1 (`RUN_SETTINGS_DEFAULTS`, test 1).
- Storage under `run_settings`, keyed verbatim: Task 2 (tests 8, 9, 10). Other keys preserved by set-run-settings: Task 2 (test 10). set-project keeps `run_settings`: Task 2 (test 11, which also runs the interleaving the other way round). Unknown keys inside an entry preserved: Task 2 (test 10).
- `get-run-settings`: exactly three keys and exit 0 is Task 1 (tests 1, 4). Each damaged-file case is Task 1 (test 2). Per-field coercion with the whole list rejected, and strict booleans checked as JSON text, is Task 1 (test 3). Legacy read is Task 1 (test 5). Writes nothing is Task 1 (Review Focus 4).
- `set-run-settings`: partial update is Task 2 (test 7). `{}` creating an empty entry is Task 2 (test 8). Every listed validation failure, with exit 2 and the file unchanged or absent, is Task 2 (test 13, split into two parametrised tests over `BAD_UPDATES`). The key-naming error is Task 2 (test 14). Verbatim strings with non-ASCII sent raw in argv are Task 2 (test 12). The legacy carry-forward is Task 2 (test 18). Corrupt-file replacement is Task 2 (Review Focus 2). Temp files, mode `0o600` and the OSError exit 1 are Task 2 (tests 15-17). Stored values not rewritten is Task 2 (`..._keeps_damaged_stored_fields_it_was_not_given`).
- Command line: the arity, empty-root and extra-argument checks and the exact USAGE are Task 1 (test 19, including the set-run-settings shapes, which hit the USAGE fallback until Task 2 adds the branch, and still do after it). Test 20 (`test_bad_usage_is_rejected`) is left unedited and runs in every Step 4.
- Docstring listing all four commands with the never-fails / validates / atomic / keeps-keys statements: Task 2, Step 3.
- ASCII: Task 2, Step 4 grep. The architecture tier runs in both Step 4s. `bash tests/run.sh`: Task 2, Step 4.
- Out of scope: no step touches any other file. The stray blank line at lines 20-22 is explicitly kept.

**Placeholder scan.** No "TBD", "TODO" or "similar to". Every code step carries the full code.

**Type consistency.** `RUN_SETTINGS_DEFAULTS`, `valid_verify` and `USAGE` are defined in Task 1 and used by name in Task 2. `parse_run_settings` returns `(dict, None)` or `(None, str)`, and `cmd_set_run_settings` branches on `update is None`. `save(data)` returns `emit(...)`'s code, as `cmd_set_project` did. Test helpers `USAGE`, `DEFAULTS` and `write_state` are defined in Task 1, ahead of their Task 2 uses. `BAD_UPDATES` is defined in Task 2, directly above the two tests that use it.

**Staged check.** I extracted both tasks' code blocks from this plan, applied them to a scratch copy of the repo, and ran them. Task 1 red: 26 failed / 21 passed. Task 1 green: 59 passed (viewer-state plus architecture). Task 2 red: 24 failed / 77 passed. Task 2 green: 101 passed in `test_viewer_state.py`, 113 with architecture. The ASCII grep found no matches. `bash tests/run.sh` exited 0.
<!-- task-pipeline: validated -->
