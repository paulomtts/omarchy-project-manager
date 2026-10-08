# 2.4 `viewer-state.py`: global run settings — design

Card `25dbf867`, a subtask of story `d1d142ee` ("Global runs backend"). It is
blocked by 2.3 (`5b5c2a1a`, `runs-watch.py`, which landed at `c0379fa`); the
two share no code. Parent spec:
`docs/superpowers/specs/2026-10-05-runs-all-projects-design.md` (below:
**parent**). Layering: `docs/architecture.md` (below: **arch**). The script
being changed is `core/backend/projects/viewer-state.py` (below: **script**).
Its tests are `tests/core/backend/projects/test_viewer_state.py` (below:
**tests**).

## Goal

`viewer-state.py` gains two commands, `get-global-settings` and
`set-global-settings <json>`. They hold one viewer-wide boolean,
`notifyOnEscalation`, under a new top-level `global_settings` key of the state
file. When nothing valid is stored, `get-global-settings` derives the value
from the per-project values already on disk (the migration read). Every
existing command keeps its behaviour, including the per-project
`notifyOnEscalation` in `get-run-settings` / `set-run-settings`.

## Where the code stands today (head `c0379fa`)

- script L5-8 lists four commands; `USAGE` (L37-38) is
  `usage: viewer-state.py get | set-project <root_path> | get-run-settings <root_path> | set-run-settings <root_path> <json>`.
  tests L114-115 repeat that string as `USAGE`, and
  `test_run_settings_bad_usage_is_rejected` (tests L255-262) compares it exactly.
- `load()` (L57-67) reads the new file, else the legacy `brd-viewer/state.json`,
  and returns `{}` for any unreadable or non-object content.
- `valid_boolean` (L88-89) is `isinstance(value, bool)`.
- `parse_run_settings` (L127-140) holds the four run-settings refusal sentences;
  tests assert them exactly, so they do not change.
- `save(data)` (L143-151) writes atomically with mode `0o600` and emits
  `{"ok": true}` (exit 0) or `{"ok": false, "error": <OSError text>}` (exit 1).
- `main` (L180-189) dispatches on exact argv length; anything else is
  `{"ok": false, "error": USAGE}`, exit 2.
- Nothing in the plugin calls `get-global-settings` / `set-global-settings` yet.
  `core/stores/RunStore.qml` still reads and writes the per-project value
  (arch L91); moving it to the new commands is a later store card.

## Inherited constraints

| constraint | source |
|---|---|
| Notify on escalation is one viewer-wide switch, read with `viewer-state.py get-global-settings` and written with `set-global-settings` | parent L73-76 |
| The first read, when nothing is stored, is true when any project's stored value is true | parent L76-77 |
| Backend pytest covers `viewer-state.py` global settings: default, migration read, round trip | parent L183-184 |
| `core/backend/**` imports only the Python stdlib and `core/backend/common` | arch L12 |
| A helper prints one JSON line, inserts its parent on `sys.path` for `common`, duplicates no helper; its pytest lives under `tests/core/backend/<domain>/` | arch L214-216 |
| No second `def emit(` or `def write_atomic(`: output goes through `common.json_line.emit`, writes through `common.atomic_write.write_atomic` | `tests/architecture/test_layers.py`; script L32-33 |
| Atomic write, other keys kept, unknown keys and non-booleans refused like `set-run-settings` | card |
| `get-global-settings` never fails | card |
| The per-project `notifyOnEscalation` stays readable and writable in `get-run-settings` / `set-run-settings` | card |
| The module docstring and `USAGE` are updated | card |
| Docstrings and comments state the contract only, with no narrative; TDD with tests first; `bash tests/run.sh` green, including `tests/architecture` | card |

Known contradiction, resolved here: parent L77 says "The per-project value is
no longer read or written." The card, which came later, says the script keeps
reading and writing it and only the plugin stops using it. The card wins: the
script's run-settings commands are unchanged. This card does not edit the
parent spec.

## Behaviour

### CLI

```
viewer-state.py get-global-settings
viewer-state.py set-global-settings <json>
```

`USAGE` becomes exactly:

```
usage: viewer-state.py get | set-project <root_path> | get-run-settings <root_path> | set-run-settings <root_path> <json> | get-global-settings | set-global-settings <json>
```

The tests' `USAGE` constant changes to the same string. Every bad argv for the
new commands prints `{"ok": false, "error": USAGE}`, exits 2, and writes
nothing:

| argv | why it is usage |
|---|---|
| `get-global-settings x` | takes no argument |
| `set-global-settings` | the JSON is missing |
| `set-global-settings {} x` | one argument too many |

`set-global-settings ""` is not usage: the empty string reaches the JSON
parse and is refused as not valid JSON (below), exactly as
`set-run-settings /p ""` is today.

### `get-global-settings`

Prints one line, `{"notifyOnEscalation": <true|false>}`, and exits 0. It never
fails and never writes, creates or repairs any file or directory.

It reads the same data `load()` returns (the new file, else the legacy
`brd-viewer/state.json`; `{}` for a missing, unreadable or non-object file).
Then:

1. **Stored value.** If `data["global_settings"]` is an object and its
   `notifyOnEscalation` is a JSON boolean, that boolean is the answer. A stored
   `false` wins over the migration read just as a stored `true` does.
2. **Migration read.** Otherwise the answer is `true` when at least one value
   of `data["run_settings"]` is an object whose `notifyOnEscalation` is the
   JSON boolean `true`, and `false` otherwise. Only the boolean `true` counts:
   `1`, `"true"`, `"yes"`, `null`, a list or an object do not. A
   `run_settings` that is not an object, and entries that are not objects,
   count as no `true`. Every root counts; no root is preferred.
3. With neither, the answer is `false`.

A `global_settings` that is present but damaged (not an object; an object
without the key; a key holding `1`, `"true"`, `null`, a list) falls through to
the migration read. Keys of `global_settings` other than
`notifyOnEscalation` are ignored and never printed.

### `set-global-settings <json>`

The argument must be a JSON object. Each key must be `notifyOnEscalation`, and
its value must be a JSON boolean. The whole object is checked before anything
is read or written. The first problem found is refused with
`{"ok": false, "error": <sentence>}`, exit 2, and the state file is left
byte-for-byte as it was (no file or directory is created when there was
none). The sentences, checked in this order:

| input | sentence |
|---|---|
| not valid JSON (includes `""` and a truncated object) | `The global settings are not valid JSON.` |
| valid JSON but not an object (`[]`, `"x"`, `5`, `true`, `null`) | `The global settings must be a JSON object.` |
| a key other than `notifyOnEscalation` (first in input order) | `Unknown global setting: <key>.` |
| `notifyOnEscalation` not a boolean (`0`, `1`, `"true"`, `null`, `[]`, `{}`) | `notifyOnEscalation must be true or false.` |

A duplicated key follows Python's `json.loads`: the last value wins, and only
that value is checked.

On an accepted object:

- The state is loaded as `load()` does (so a legacy-only file is carried
  forward into the new file, and a corrupt or non-object file is replaced by
  an object holding only `global_settings`).
- If `data["global_settings"]` is not an object, it is replaced by `{}`.
- The given keys are set in it; any key not given (including a damaged stored
  `notifyOnEscalation` when the input is `{}`) is kept as stored.
- Every other top-level key (`last_project`, `run_settings`, unknown keys) is
  kept unchanged. In particular no project's per-project
  `notifyOnEscalation` is changed.
- The file is written with `save()`: atomically, a newly created file has mode
  `0o600`, no temporary file is left in the directory, success prints
  `{"ok": true}` (exit 0), and an `OSError` prints `{"ok": false, "error":
  <text>}` (exit 1).

`{}` is accepted. It writes the file (creating `global_settings: {}` when
there was none) and leaves `get-global-settings` answering from the migration
read.

### Existing commands

`get`, `set-project`, `get-run-settings` and `set-run-settings` behave exactly
as today, with every existing test unchanged except the `USAGE` constant.
`notifyOnEscalation` stays one of the seven run settings with default `false`
and the sentence `notifyOnEscalation must be true or false.`. `set-project`
and `set-run-settings` keep a stored `global_settings` because they already
keep every other key; tests pin that. Setting a project's
`notifyOnEscalation` after a global value is stored does not change the global
answer.

### Docstring

The module docstring lists all six commands in the order of `USAGE`. It says,
as contract only: global settings live under `"global_settings"`; there is one,
`notifyOnEscalation`, a boolean; `get-global-settings` never fails and, when no
boolean is stored, answers true when any project's stored run-settings
`notifyOnEscalation` is true, else false; `set-global-settings` takes a JSON
object, validates every key before writing anything, changes only the keys
given and keeps any other keys in the file. The opening summary line covers
the viewer-wide settings too. The existing run-settings text stays.

### Implementation latitude (for the planner)

The refusal sentences for run settings must stay exactly as they are. The
planner may generalise `parse_run_settings` (for example by passing the
setting noun, the allowed keys, the validators and the refusals) or write a
sibling parser; either way `valid_boolean` and the existing
`"notifyOnEscalation must be true or false."` sentence are reused, not
duplicated. No new module and no new helper outside the script.

## Error paths

| condition | output | exit | file |
|---|---|---|---|
| bad argv | `{"ok": false, "error": USAGE}` | 2 | untouched |
| `set-global-settings` refusal | `{"ok": false, "error": <sentence above>}` | 2 | untouched |
| state directory not writable | `{"ok": false, "error": <OSError text>}` | 1 | untouched |
| corrupt / non-object / unreadable state file on `get-global-settings` | migration read over `{}`: `{"notifyOnEscalation": false}` | 0 | untouched |

## Tests

All new tests go in **tests**, in a new `# --- global settings ---` section at
the end, using the existing `env`, `run`, `state_file` and `write_state`
helpers. Tier for every test: **backend pytest** (`tests/core/backend/projects/`,
run by `bash tests/run.sh`). Why: the deliverable is a CLI whose contract is
its argv, its one JSON stdout line, its exit code and the state file it leaves,
which a subprocess test observes directly (parent L181-184 assigns this script
to backend pytest). No QML test is added: nothing in the plugin calls the new
commands in this card.

Default:

1. `get-global-settings` with no state file prints `{"notifyOnEscalation": false}`, exit 0.
2. `get-global-settings` writes nothing: `XDG_STATE_HOME` does not exist afterwards.
3. Corrupt files (`""`, `"not json"`, `"[1]"`, `'"text"'`) give `false`, exit 0, and the file bytes are unchanged.

Migration read:

4. One project with `notifyOnEscalation: true` among others with `false` or nothing gives `true`; the `true` project may be any root (parametrize its position: first, last).
5. Every project `false`, or no project holding the key, or `run_settings: {}`, gives `false`.
6. Non-boolean truthy values (`1`, `"true"`, `"yes"`, `[true]`, `{"x": true}`) in every project give `false`.
7. A damaged `run_settings` (`5`, `"x"`, `[]`, `null`) or damaged entries (`{"/p": "x"}`, `{"/p": null}`, `{"/p": [true]}`) beside one good entry with `true` gives `true`; with no good entry, `false`.
8. Damaged `global_settings` (`5`, `"x"`, `[]`, `null`, `{}`, `{"notifyOnEscalation": 1}`, `{"notifyOnEscalation": "true"}`, `{"notifyOnEscalation": null}`) with a project `true` gives `true` (falls through to the migration read).
9. The migration reads the legacy `brd-viewer/state.json` when no new file exists, and writes nothing.
10. A stored `global_settings.notifyOnEscalation` of `false` with a project `true` gives `false`; a stored `true` with every project `false` gives `true`.
11. Unknown keys inside `global_settings` are not printed: output is exactly `{"notifyOnEscalation": …}`.

Round trip:

12. `set-global-settings '{"notifyOnEscalation": true}'` prints `{"ok": true}`, exit 0, then `get-global-settings` gives `true`; then `false` gives `false` (parametrize over both orders).
13. A set `false` sticks while a project's run settings hold `true` (the stored value wins after a write).
14. `set-global-settings '{}'` is accepted, creates `global_settings: {}` on a missing file, and `get-global-settings` still answers from the migration read.
15. `set-global-settings` keeps `last_project`, `run_settings` (byte-equal entries, including each project's `notifyOnEscalation`) and an unknown top-level key; the file equals the old object plus `global_settings`.
16. `set-global-settings` replaces a damaged `global_settings` (`5`, `"x"`, `[]`, `null`) with an object holding the given key.
17. `set-global-settings '{}'` keeps unknown keys and a damaged stored `notifyOnEscalation` inside `global_settings` as they were.
18. `set-global-settings` carries a legacy-only file forward: the new file holds the legacy keys plus `global_settings`, and the legacy file is unchanged.
19. `set-global-settings` over a corrupt file writes `{"global_settings": {"notifyOnEscalation": true}}`.
20. No temporary file is left (`state.json` is the only entry in its directory), and a newly created file has mode `0o600`.
21. An unwritable state directory gives exit 1, `ok: false` and a non-empty `error` (skipped as root, like tests L70-79).
22. `set-project` and `set-run-settings` keep a stored `global_settings`; `set-run-settings /p '{"notifyOnEscalation": true}'` after a stored global `false` leaves `get-global-settings` at `false` and `get-run-settings /p` at `true`.

Refusals:

23. Each refused input from the sentence table (invalid JSON including `""` and `'{"notifyOnEscalation": tru'`; `[]`, `"x"`, `5`, `true`, `null`; `{"notify": true}`, `{"notifyOnEscalation": true, "verify": []}`; `{"notifyOnEscalation": 0}`, `1`, `"true"`, `null`, `[]`, `{}`) gives exit 2 and exactly its sentence; with no state file, `XDG_STATE_HOME` does not exist afterwards.
24. The same inputs over an existing file leave its bytes unchanged and leave `state.json` the only entry in its directory.
25. The first bad key in input order is the one named: `{"a": 1, "b": 2}` names `a`; `{"notifyOnEscalation": 0, "z": true}` gives the boolean sentence.
26. Bad usage (`get-global-settings x`; `set-global-settings`; `set-global-settings {} x`) gives exit 2, `{"ok": false, "error": USAGE}`, and writes nothing.

Existing tests: only the `USAGE` constant at tests L114-115 changes. All other
existing tests, including the run-settings tests that cover the per-project
`notifyOnEscalation`, must pass unchanged.

## Out of scope

- `core/stores/RunStore.qml` reading and writing the switch through the new
  commands, its `tst_run_store.qml` tests, and the arch L91 / L165 sentences
  that call the switch per project: these belong to the store and docs cards
  of this milestone.
- The Runs screen showing the switch with no project open (parent L77-78):
  a UI card.
- README.md (L229 only mentions the last project) and the parent spec text.
- Removing or deprecating the per-project `notifyOnEscalation` in the script.
- Any other global setting: `global_settings` holds exactly one key.
- `runs-watch.py`, `runs-snapshot*.py` and every other sibling card of story
  `d1d142ee`.

---

# 2.4 viewer-state.py: global run settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `core/backend/projects/viewer-state.py` gains `get-global-settings` and `set-global-settings <json>`, holding one viewer-wide boolean `notifyOnEscalation` under a top-level `global_settings` key, with a migration read from the per-project values when nothing valid is stored.

**Architecture:** Both commands live in the existing script. `get-global-settings` reads `load()` and answers from `global_settings.notifyOnEscalation` when it is a boolean, else from "any `run_settings` entry holds the boolean `true`". `set-global-settings` reuses a generalised `parse_settings(text, noun, valid, refusals)` (the old `parse_run_settings`, now taking the setting noun, the validators and the refusal sentences), then merges the given keys into `data["global_settings"]` and writes with the existing `save()`. `load()` additionally treats a state file nested past the recursion limit as unreadable, so `get-global-settings` truly never fails.

**Tech Stack:** Python 3 stdlib only (`json`, `os`, `sys`); `common.json_line.emit`, `common.atomic_write.write_atomic`; pytest subprocess tests.

**Spec:** `docs/superpowers/specs/2-4-viewer-state-py-25dbf867.md` (prepended above).

## Global Constraints

- `core/backend/**` imports only the Python stdlib and `core/backend/common`.
- No second `def emit(` or `def write_atomic(`: output goes through `common.json_line.emit`, writes through `common.atomic_write.write_atomic` (`tests/architecture/test_layers.py`).
- No new module and no new helper outside the script.
- `USAGE` is exactly `usage: viewer-state.py get | set-project <root_path> | get-run-settings <root_path> | set-run-settings <root_path> <json> | get-global-settings | set-global-settings <json>`.
- Refusal sentences, exactly: `The global settings are not valid JSON.` / `The global settings must be a JSON object.` / `Unknown global setting: <key>.` / `notifyOnEscalation must be true or false.`
- The run-settings refusal sentences stay exactly as they are; `valid_boolean` and the existing `"notifyOnEscalation must be true or false."` sentence are reused, not duplicated.
- `get-global-settings` never fails and never writes, creates or repairs any file or directory.
- Existing commands behave as today; the only existing test that changes is the `USAGE` constant at `tests/core/backend/projects/test_viewer_state.py:115-116`.
- Docstrings and comments state the contract only, with no narrative.
- `bash tests/run.sh` green, including `tests/architecture`.
- Never run the test suite as anything but the current user (the unwritable-directory tests are skipped as root).

## Review Focus

1. **A state file nested past Python's recursion limit** (e.g. `"[" * 100000`): `json.load` raises `RecursionError`, which `load()` does not catch today, so `get-global-settings` would print a traceback. Expected: `{"notifyOnEscalation": false}`, exit 0, file untouched. Owned by Task 1 (`load()` catches `RecursionError`; test `test_get_global_settings_treats_bad_files_as_false` has a `nested-past-the-recursion-limit` case).
2. **An unreadable state file** (mode `000`): expected `false`, exit 0, no traceback. Owned by Task 1 (`test_get_global_settings_unreadable_file_is_false`, skipped as root).
3. **The new file exists without a `true` while the legacy `brd-viewer/state.json` holds a project `true`**: the new file wins, as for every other read. Expected `false`. Owned by Task 1 (`test_get_global_settings_new_file_wins_over_legacy`).
4. **Python's `1 == True` hiding a leaked non-boolean**: a stored `global_settings.notifyOnEscalation: 1` with no project `true` must print `false`, and output is compared as JSON text so a `1` cannot pass for `true`. Owned by Task 1 (`get_global` helper compares JSON text; `test_damaged_global_settings_with_no_project_true_is_false`).
5. **Inputs to `set-global-settings` that break `json.loads` other than by syntax** (an object nested past the recursion limit; an integer of more than 4300 digits) and a **non-ASCII unknown key** (`{"café": true}`): expected exactly `The global settings are not valid JSON.` / `Unknown global setting: café.`, exit 2, nothing written. Owned by Task 2 (cases in `GLOBAL_REFUSALS`).

## File Structure

- Modify: `core/backend/projects/viewer-state.py` — docstring, `USAGE`, `load()`, new `cmd_get_global_settings`, `parse_run_settings` → `parse_settings`, new `GLOBAL_SETTINGS_VALID` / `GLOBAL_SETTINGS_REFUSALS`, new `cmd_set_global_settings`, two `main` branches.
- Modify: `tests/core/backend/projects/test_viewer_state.py` — the `USAGE` constant (lines 115-116) and a new `# --- global settings ---` section appended at the end of the file.

Run tests with (python3 here has no pytest, so uv's throwaway env is used, as `tests/run.sh` does):

`uv run --with pytest python3 -m pytest tests/core/backend/projects/test_viewer_state.py -q`

---

### Task 1: `get-global-settings`, the new `USAGE`, and a `load()` that survives deep nesting

**Files:**
- Modify: `core/backend/projects/viewer-state.py:1-26` (docstring), `:37-38` (`USAGE`), `:57-67` (`load`), after `:124` (new `cmd_get_global_settings`), `:180-189` (`main`)
- Test: `tests/core/backend/projects/test_viewer_state.py:115-116` (`USAGE`) and a new section at the end of the file

**Interfaces:**
- Consumes: `load() -> dict`, `valid_boolean(value) -> bool`, `emit(payload, code) -> int` (all existing in the script).
- Produces: `cmd_get_global_settings() -> int` (prints `{"notifyOnEscalation": bool}`, returns 0); `main` routes `["get-global-settings"]` to it; `USAGE` is the six-command string. Tests produce helpers `get_global(env) -> (int, str)`, `GLOBAL_TRUE`, `GLOBAL_FALSE` used by Task 2.

- [ ] **Step 1: Change the tests' `USAGE` constant**

In `tests/core/backend/projects/test_viewer_state.py`, replace lines 115-116:

```python
USAGE = ("usage: viewer-state.py get | set-project <root_path> | get-run-settings <root_path>"
         " | set-run-settings <root_path> <json>")
```

with:

```python
USAGE = ("usage: viewer-state.py get | set-project <root_path> | get-run-settings <root_path>"
         " | set-run-settings <root_path> <json> | get-global-settings | set-global-settings <json>")
```

- [ ] **Step 2: Append the failing `get-global-settings` tests**

Append to the end of `tests/core/backend/projects/test_viewer_state.py`:

```python


# --- global settings ---------------------------------------------------------------

GLOBAL_TRUE = '{"notifyOnEscalation": true}'
GLOBAL_FALSE = '{"notifyOnEscalation": false}'


def get_global(env):
    """get-global-settings as (exit code, output as JSON text): a 1 cannot pass for true, nor extra keys slip by."""
    code, result = run(env, "get-global-settings")
    return code, json.dumps(result)


def legacy_file(env):
    return Path(env["XDG_STATE_HOME"]) / "brd-viewer" / "state.json"


def test_get_global_settings_with_no_file_is_false(env):
    assert get_global(env) == (0, GLOBAL_FALSE)


def test_get_global_settings_writes_nothing(env):
    run(env, "get-global-settings")
    assert not Path(env["XDG_STATE_HOME"]).exists()


@pytest.mark.parametrize("content", ["", "not json", "[1]", '"text"',
                                     pytest.param("[" * 100000, id="nested-past-the-recursion-limit")])
def test_get_global_settings_treats_bad_files_as_false(env, content):
    write_state(env, content)
    before = state_file(env).read_bytes()
    assert get_global(env) == (0, GLOBAL_FALSE)
    assert state_file(env).read_bytes() == before


@pytest.mark.skipif(os.geteuid() == 0, reason="root ignores file permissions")
def test_get_global_settings_unreadable_file_is_false(env):
    write_state(env, {"global_settings": {"notifyOnEscalation": True}})
    state_file(env).chmod(0o000)
    try:
        assert get_global(env) == (0, GLOBAL_FALSE)
    finally:
        state_file(env).chmod(0o600)


@pytest.mark.parametrize("run_settings", [
    {"/a": {"notifyOnEscalation": True}, "/b": {"notifyOnEscalation": False}, "/c": {"verify": ["x"]}},
    {"/a": {"notifyOnEscalation": False}, "/b": {"verify": ["x"]}, "/c": {"notifyOnEscalation": True}},
], ids=["true-first", "true-last"])
def test_migration_read_is_true_when_any_project_is_true(env, run_settings):
    write_state(env, {"run_settings": run_settings})
    assert get_global(env) == (0, GLOBAL_TRUE)


@pytest.mark.parametrize("run_settings", [
    {"/a": {"notifyOnEscalation": False}, "/b": {"notifyOnEscalation": False}},
    {"/a": {"verify": ["x"]}, "/b": {}},
    {},
], ids=["all-false", "no-key", "empty"])
def test_migration_read_is_false_when_no_project_is_true(env, run_settings):
    write_state(env, {"run_settings": run_settings})
    assert get_global(env) == (0, GLOBAL_FALSE)


@pytest.mark.parametrize("value", [1, "true", "yes", [True], {"x": True}])
def test_migration_read_counts_only_the_boolean_true(env, value):
    write_state(env, {"run_settings": {"/a": {"notifyOnEscalation": value}, "/b": {"notifyOnEscalation": value}}})
    assert get_global(env) == (0, GLOBAL_FALSE)


@pytest.mark.parametrize("run_settings", [5, "x", [], None])
def test_migration_read_with_damaged_run_settings_is_false(env, run_settings):
    write_state(env, {"run_settings": run_settings})
    assert get_global(env) == (0, GLOBAL_FALSE)


@pytest.mark.parametrize("entry", ["x", None, [True]])
def test_migration_read_skips_damaged_entries(env, entry):
    write_state(env, {"run_settings": {"/bad": entry, "/good": {"notifyOnEscalation": True}}})
    assert get_global(env) == (0, GLOBAL_TRUE)
    write_state(env, {"run_settings": {"/bad": entry}})
    assert get_global(env) == (0, GLOBAL_FALSE)


DAMAGED_GLOBAL_SETTINGS = [5, "x", [], None, {}, {"notifyOnEscalation": 1}, {"notifyOnEscalation": "true"},
                           {"notifyOnEscalation": None}]


@pytest.mark.parametrize("stored", DAMAGED_GLOBAL_SETTINGS)
def test_damaged_global_settings_fall_through_to_the_migration_read(env, stored):
    write_state(env, {"global_settings": stored, "run_settings": {"/p": {"notifyOnEscalation": True}}})
    assert get_global(env) == (0, GLOBAL_TRUE)


@pytest.mark.parametrize("stored", DAMAGED_GLOBAL_SETTINGS)
def test_damaged_global_settings_with_no_project_true_is_false(env, stored):
    write_state(env, {"global_settings": stored, "run_settings": {"/p": {"notifyOnEscalation": False}}})
    assert get_global(env) == (0, GLOBAL_FALSE)


def test_migration_read_uses_the_legacy_file(env):
    legacy_file(env).parent.mkdir(parents=True)
    legacy_file(env).write_text('{"run_settings": {"/p": {"notifyOnEscalation": true}}}')
    assert get_global(env) == (0, GLOBAL_TRUE)
    assert not state_file(env).parent.exists()
    assert legacy_file(env).read_text() == '{"run_settings": {"/p": {"notifyOnEscalation": true}}}'


def test_get_global_settings_new_file_wins_over_legacy(env):
    legacy_file(env).parent.mkdir(parents=True)
    legacy_file(env).write_text('{"run_settings": {"/p": {"notifyOnEscalation": true}}}')
    write_state(env, {"last_project": "/p"})
    assert get_global(env) == (0, GLOBAL_FALSE)


def test_stored_global_value_wins_over_the_migration_read(env):
    write_state(env, {"global_settings": {"notifyOnEscalation": False},
                      "run_settings": {"/p": {"notifyOnEscalation": True}}})
    assert get_global(env) == (0, GLOBAL_FALSE)
    write_state(env, {"global_settings": {"notifyOnEscalation": True},
                      "run_settings": {"/p": {"notifyOnEscalation": False}}})
    assert get_global(env) == (0, GLOBAL_TRUE)


def test_get_global_settings_prints_only_notify_on_escalation(env):
    write_state(env, {"global_settings": {"notifyOnEscalation": True, "theme": "dark"}})
    assert get_global(env) == (0, GLOBAL_TRUE)


@pytest.mark.parametrize("args", [
    ("get-global-settings", "x"), ("set-global-settings",), ("set-global-settings", "{}", "x"),
])
def test_global_settings_bad_usage_is_rejected(env, args):
    assert run(env, *args) == (2, {"ok": False, "error": USAGE})
    assert not Path(env["XDG_STATE_HOME"]).exists()
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/projects/test_viewer_state.py -q`

Expected: FAIL. `test_run_settings_bad_usage_is_rejected` (7 cases) and `test_global_settings_bad_usage_is_rejected` (3 cases) fail on the `USAGE` text; every `get-global-settings` test fails because the script answers `{"ok": false, "error": ...}` with exit 2 (e.g. `assert (2, '{"ok": false, ...}') == (0, '{"notifyOnEscalation": false}')`). `test_get_global_settings_writes_nothing` passes already (the script writes nothing on usage) — that is fine. All other existing tests pass.

- [ ] **Step 4: Update `USAGE` in the script**

In `core/backend/projects/viewer-state.py`, replace lines 37-38:

```python
USAGE = ("usage: viewer-state.py get | set-project <root_path> | get-run-settings <root_path>"
         " | set-run-settings <root_path> <json>")
```

with:

```python
USAGE = ("usage: viewer-state.py get | set-project <root_path> | get-run-settings <root_path>"
         " | set-run-settings <root_path> <json> | get-global-settings | set-global-settings <json>")
```

- [ ] **Step 5: Make `load()` treat a too-deeply-nested file as unreadable**

Replace in `load()`:

```python
        except (OSError, ValueError):
            return {}
```

with:

```python
        except (OSError, ValueError, RecursionError):
            return {}
```

- [ ] **Step 6: Add `cmd_get_global_settings`**

Insert directly after `cmd_get_run_settings` (after the line `    return emit(result, 0)` that ends it, before `def parse_run_settings`):

```python


def cmd_get_global_settings():
    data = load()
    stored = data.get("global_settings")
    value = stored.get("notifyOnEscalation") if isinstance(stored, dict) else None
    if not valid_boolean(value):
        settings = data.get("run_settings")
        entries = settings.values() if isinstance(settings, dict) else ()
        value = any(isinstance(entry, dict) and entry.get("notifyOnEscalation") is True for entry in entries)
    return emit({"notifyOnEscalation": value}, 0)
```

- [ ] **Step 7: Route the command in `main`**

In `main`, insert before the final `return emit({"ok": False, "error": USAGE}, 2)`:

```python
    if argv == ["get-global-settings"]:
        return cmd_get_global_settings()
```

- [ ] **Step 8: Update the module docstring for the six commands and the read**

Replace the whole docstring (lines 2-26) with:

```python
"""Remembers which brd project the panel was last showing, each project's run
settings, and the viewer-wide global settings.

    viewer-state.py get
    viewer-state.py set-project <root_path>
    viewer-state.py get-run-settings <root_path>
    viewer-state.py set-run-settings <root_path> <json>
    viewer-state.py get-global-settings
    viewer-state.py set-global-settings <json>

State lives in ${XDG_STATE_HOME:-~/.local/state}/omarchy-project-manager/state.json
(reads fall back to the old brd-viewer/state.json until a new one is written). QML
cannot write files, hence this helper. Prints one JSON line. `get`,
`get-run-settings` and `get-global-settings` never fail (a missing or corrupt file,
or a damaged value, just means the default); `set-project` and `set-run-settings`
write atomically and keep any other keys already in the file. Run settings live
under "run_settings", keyed by the root path verbatim. There are seven, each read
on its own:
verify (a list of non-empty strings, default []), allowNoVerification and
notifyOnEscalation (booleans, default false), prefixHistory (a list of at most 20
non-empty strings, most recent first, default []), parallelism (a whole number
>= 1, default 4), confirmDispatch (a boolean, default true) and prefixByMilestone
(an object mapping each milestone id to a non-empty prefix string, default {}).
`set-run-settings` takes a JSON object with any of them, validates every key
before writing anything, and changes only the keys given; a list given replaces
the stored list wholesale, and a prefixByMilestone given is merged into the
stored map per milestone id (a stored map that is not valid is replaced).
Global settings live under "global_settings". There is one, notifyOnEscalation,
a boolean; when no boolean is stored, `get-global-settings` answers true when any
project's stored run-settings notifyOnEscalation is true, else false.
"""
```

- [ ] **Step 9: Run the tests to verify they pass**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/projects/test_viewer_state.py -q`

Expected: PASS, every test (`set-global-settings` is still unrouted, but the only tests calling it in this task are the usage tests, which expect `USAGE`).

- [ ] **Step 10: Run the architecture tests**

Run: `uv run --with pytest python3 -m pytest tests/architecture -q`

Expected: PASS.

- [ ] **Step 11: Commit**

```bash
git add core/backend/projects/viewer-state.py tests/core/backend/projects/test_viewer_state.py
git commit -m "feat(viewer-state): get-global-settings with a migration read from per-project values"
```

---

### Task 2: `set-global-settings`, through a shared settings parser

**Files:**
- Modify: `core/backend/projects/viewer-state.py` — docstring (the two sentences changed below), `RUN_SETTINGS_REFUSALS` neighbourhood (new constants), `parse_run_settings` → `parse_settings`, `cmd_set_run_settings` (its parse call), new `cmd_set_global_settings`, `main`
- Test: `tests/core/backend/projects/test_viewer_state.py` (append to the `# --- global settings ---` section)

**Interfaces:**
- Consumes (from Task 1): tests' `get_global(env) -> (int, str)`, `GLOBAL_TRUE`, `GLOBAL_FALSE`, `legacy_file(env) -> Path`, `USAGE`; existing `run`, `env`, `state_file`, `write_state`, `same_json`, `DEFAULTS`. Script's `load()`, `save(data) -> int`, `valid_boolean`, `RUN_SETTINGS_VALID`, `RUN_SETTINGS_REFUSALS`.
- Produces: `parse_settings(text: str, noun: str, valid: dict, refusals: dict) -> (dict | None, str | None)`; `GLOBAL_SETTINGS_VALID = {"notifyOnEscalation": valid_boolean}`; `GLOBAL_SETTINGS_REFUSALS = {"notifyOnEscalation": RUN_SETTINGS_REFUSALS["notifyOnEscalation"]}`; `cmd_set_global_settings(text: str) -> int`; `main` routes `["set-global-settings", <json>]`.

- [ ] **Step 1: Append the failing `set-global-settings` tests**

Append to the end of `tests/core/backend/projects/test_viewer_state.py`:

```python


@pytest.mark.parametrize("first, second", [(True, False), (False, True)])
def test_set_then_get_global_settings_round_trips(env, first, second):
    for value in (first, second):
        assert run(env, "set-global-settings", json.dumps({"notifyOnEscalation": value})) == (0, {"ok": True})
        assert get_global(env) == (0, json.dumps({"notifyOnEscalation": value}))


def test_set_global_false_sticks_while_a_project_is_true(env):
    write_state(env, {"run_settings": {"/p": {"notifyOnEscalation": True}}})
    assert run(env, "set-global-settings", '{"notifyOnEscalation": false}') == (0, {"ok": True})
    assert get_global(env) == (0, GLOBAL_FALSE)
    assert run(env, "get-run-settings", "/p") == (0, {**DEFAULTS, "notifyOnEscalation": True})


def test_set_global_settings_empty_object_is_accepted(env):
    assert run(env, "set-global-settings", "{}") == (0, {"ok": True})
    assert json.loads(state_file(env).read_text()) == {"global_settings": {}}
    assert get_global(env) == (0, GLOBAL_FALSE)
    write_state(env, {"run_settings": {"/p": {"notifyOnEscalation": True}}})
    assert run(env, "set-global-settings", "{}") == (0, {"ok": True})
    assert json.loads(state_file(env).read_text()) == {
        "run_settings": {"/p": {"notifyOnEscalation": True}}, "global_settings": {}}
    assert get_global(env) == (0, GLOBAL_TRUE)


def test_set_global_settings_preserves_other_keys(env):
    before = {"last_project": "/p", "other": {"x": 1},
              "run_settings": {"/a": {"notifyOnEscalation": True, "verify": ["a"]},
                               "/b": {"notifyOnEscalation": False, "future": 1}}}
    write_state(env, before)
    assert run(env, "set-global-settings", '{"notifyOnEscalation": false}') == (0, {"ok": True})
    assert same_json(json.loads(state_file(env).read_text()),
                     {**before, "global_settings": {"notifyOnEscalation": False}})


@pytest.mark.parametrize("stored", [5, "x", [], None])
def test_set_global_settings_replaces_a_damaged_global_settings(env, stored):
    write_state(env, {"last_project": "/p", "global_settings": stored})
    assert run(env, "set-global-settings", '{"notifyOnEscalation": true}') == (0, {"ok": True})
    assert same_json(json.loads(state_file(env).read_text()),
                     {"last_project": "/p", "global_settings": {"notifyOnEscalation": True}})


def test_set_global_settings_keeps_keys_it_was_not_given(env):
    stored = {"global_settings": {"notifyOnEscalation": 1, "theme": "dark"}}
    write_state(env, stored)
    assert run(env, "set-global-settings", "{}") == (0, {"ok": True})
    assert same_json(json.loads(state_file(env).read_text()), stored)
    assert run(env, "set-global-settings", '{"notifyOnEscalation": true}') == (0, {"ok": True})
    assert same_json(json.loads(state_file(env).read_text()),
                     {"global_settings": {"notifyOnEscalation": True, "theme": "dark"}})


def test_set_global_settings_carries_legacy_state_forward(env):
    legacy = '{"last_project": "/home/u/old", "run_settings": {"/p": {"notifyOnEscalation": true}}}'
    legacy_file(env).parent.mkdir(parents=True)
    legacy_file(env).write_text(legacy)
    assert run(env, "set-global-settings", '{"notifyOnEscalation": false}') == (0, {"ok": True})
    assert same_json(json.loads(state_file(env).read_text()),
                     {**json.loads(legacy), "global_settings": {"notifyOnEscalation": False}})
    assert legacy_file(env).read_text() == legacy
    assert get_global(env) == (0, GLOBAL_FALSE)


@pytest.mark.parametrize("content", ["", "not json", "[1]", '"text"'])
def test_set_global_settings_replaces_a_corrupt_file(env, content):
    write_state(env, content)
    assert run(env, "set-global-settings", '{"notifyOnEscalation": true}') == (0, {"ok": True})
    assert same_json(json.loads(state_file(env).read_text()), {"global_settings": {"notifyOnEscalation": True}})


def test_set_global_settings_leaves_no_temp_files_and_a_private_file(env):
    assert run(env, "set-global-settings", '{"notifyOnEscalation": true}') == (0, {"ok": True})
    assert [p.name for p in state_file(env).parent.iterdir()] == ["state.json"]
    assert (state_file(env).stat().st_mode & 0o777) == 0o600


@pytest.mark.skipif(os.geteuid() == 0, reason="root ignores directory permissions")
def test_set_global_settings_unwritable_directory_fails_cleanly(env):
    d = state_file(env).parent
    d.mkdir(parents=True)
    d.chmod(0o500)
    try:
        code, result = run(env, "set-global-settings", '{"notifyOnEscalation": true}')
    finally:
        d.chmod(0o700)
    assert code == 1 and result["ok"] is False and result["error"]


def test_other_setters_keep_the_stored_global_settings(env):
    stored = {"notifyOnEscalation": False, "theme": "dark"}
    write_state(env, {"global_settings": stored})
    assert run(env, "set-project", "/p") == (0, {"ok": True})
    assert run(env, "set-run-settings", "/p", '{"notifyOnEscalation": true}') == (0, {"ok": True})
    assert same_json(json.loads(state_file(env).read_text())["global_settings"], stored)
    assert get_global(env) == (0, GLOBAL_FALSE)
    assert run(env, "get-run-settings", "/p") == (0, {**DEFAULTS, "notifyOnEscalation": True})


GLOBAL_NOT_JSON = "The global settings are not valid JSON."
GLOBAL_NOT_OBJECT = "The global settings must be a JSON object."
GLOBAL_NOT_BOOLEAN = "notifyOnEscalation must be true or false."
GLOBAL_REFUSALS = [
    ("", GLOBAL_NOT_JSON), ("{", GLOBAL_NOT_JSON), ('{"notifyOnEscalation": tru', GLOBAL_NOT_JSON),
    pytest.param("[" * 100000, GLOBAL_NOT_JSON, id="nested-past-the-recursion-limit"),
    pytest.param('{"notifyOnEscalation": 1%s}' % ("0" * 5000), GLOBAL_NOT_JSON, id="integer-of-5001-digits"),
    ("[]", GLOBAL_NOT_OBJECT), ('"x"', GLOBAL_NOT_OBJECT), ("5", GLOBAL_NOT_OBJECT),
    ("true", GLOBAL_NOT_OBJECT), ("null", GLOBAL_NOT_OBJECT),
    ('{"notify": true}', "Unknown global setting: notify."),
    ('{"notifyOnEscalation": true, "verify": []}', "Unknown global setting: verify."),
    ('{"café": true}', "Unknown global setting: café."),
    ('{"notifyOnEscalation": 0}', GLOBAL_NOT_BOOLEAN), ('{"notifyOnEscalation": 1}', GLOBAL_NOT_BOOLEAN),
    ('{"notifyOnEscalation": "true"}', GLOBAL_NOT_BOOLEAN), ('{"notifyOnEscalation": null}', GLOBAL_NOT_BOOLEAN),
    ('{"notifyOnEscalation": []}', GLOBAL_NOT_BOOLEAN), ('{"notifyOnEscalation": {}}', GLOBAL_NOT_BOOLEAN),
]


@pytest.mark.parametrize("update, error", GLOBAL_REFUSALS)
def test_set_global_settings_refusal_is_exact_and_creates_nothing(env, update, error):
    assert run(env, "set-global-settings", update) == (2, {"ok": False, "error": error})
    assert not Path(env["XDG_STATE_HOME"]).exists()


@pytest.mark.parametrize("update, error", GLOBAL_REFUSALS)
def test_set_global_settings_refusal_leaves_the_file_untouched(env, update, error):
    write_state(env, {"last_project": "/p", "global_settings": {"notifyOnEscalation": True}})
    before = state_file(env).read_bytes()
    assert run(env, "set-global-settings", update) == (2, {"ok": False, "error": error})
    assert state_file(env).read_bytes() == before
    assert [p.name for p in state_file(env).parent.iterdir()] == ["state.json"]


def test_set_global_settings_reports_the_first_bad_key_in_input_order(env):
    assert run(env, "set-global-settings", '{"a": 1, "b": 2}') == (
        2, {"ok": False, "error": "Unknown global setting: a."})
    assert run(env, "set-global-settings", '{"notifyOnEscalation": 0, "z": true}') == (
        2, {"ok": False, "error": GLOBAL_NOT_BOOLEAN})
    assert run(env, "set-global-settings", '{"z": true, "notifyOnEscalation": 0}') == (
        2, {"ok": False, "error": "Unknown global setting: z."})
    assert not Path(env["XDG_STATE_HOME"]).exists()


def test_set_global_settings_duplicate_key_last_wins(env):
    assert run(env, "set-global-settings", '{"notifyOnEscalation": 0, "notifyOnEscalation": true}') == (
        0, {"ok": True})
    assert get_global(env) == (0, GLOBAL_TRUE)
    assert run(env, "set-global-settings", '{"notifyOnEscalation": false, "notifyOnEscalation": 1}') == (
        2, {"ok": False, "error": GLOBAL_NOT_BOOLEAN})
    assert get_global(env) == (0, GLOBAL_TRUE)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/projects/test_viewer_state.py -q`

Expected: FAIL. Every new `set-global-settings` test that expects `{"ok": true}` or a refusal sentence fails with `(2, {"ok": False, "error": "usage: viewer-state.py get | ..."})` because the command is not routed; `test_other_setters_keep_the_stored_global_settings` already passes (it only uses existing setters) — that is fine. All Task 1 tests and every older test still pass.

- [ ] **Step 3: Generalise `parse_run_settings` into `parse_settings`**

Replace the whole `parse_run_settings` function:

```python
def parse_run_settings(text):
    """The update in `text` and None, or None and a sentence saying what is wrong."""
    try:
        update = json.loads(text)
    except (ValueError, RecursionError):
        return None, "The run settings are not valid JSON."
    if not isinstance(update, dict):
        return None, "The run settings must be a JSON object."
    for key, value in update.items():
        if key not in RUN_SETTINGS_DEFAULTS:
            return None, "Unknown run setting: %s." % key
        if not RUN_SETTINGS_VALID[key](value):
            return None, RUN_SETTINGS_REFUSALS[key]
    return update, None
```

with:

```python
def parse_settings(text, noun, valid, refusals):
    """The update in `text` and None, or None and a sentence saying what is wrong.
    `noun` names one setting ("run setting"); `valid` and `refusals` map each allowed
    key to its check and to the sentence refusing a value that fails it."""
    try:
        update = json.loads(text)
    except (ValueError, RecursionError):
        return None, "The %ss are not valid JSON." % noun
    if not isinstance(update, dict):
        return None, "The %ss must be a JSON object." % noun
    for key, value in update.items():
        if key not in valid:
            return None, "Unknown %s: %s." % (noun, key)
        if not valid[key](value):
            return None, refusals[key]
    return update, None
```

- [ ] **Step 4: Point `cmd_set_run_settings` at it**

In `cmd_set_run_settings`, replace:

```python
    update, error = parse_run_settings(text)
```

with:

```python
    update, error = parse_settings(text, "run setting", RUN_SETTINGS_VALID, RUN_SETTINGS_REFUSALS)
```

- [ ] **Step 5: Run the existing run-settings tests (refactor stays green)**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/projects/test_viewer_state.py -q -k "(run_settings or dispatch or prefix or parallelism or first_bad_key or unknown_key) and not global"`

Expected: PASS (the run-settings sentences are unchanged: "The run settings are not valid JSON.", "Unknown run setting: verfy.", ...).

- [ ] **Step 6: Add the global-settings constants**

Insert directly after the closing `}` of `RUN_SETTINGS_REFUSALS`:

```python
GLOBAL_SETTINGS_VALID = {"notifyOnEscalation": valid_boolean}
GLOBAL_SETTINGS_REFUSALS = {"notifyOnEscalation": RUN_SETTINGS_REFUSALS["notifyOnEscalation"]}
```

- [ ] **Step 7: Add `cmd_set_global_settings`**

Insert directly after `cmd_set_run_settings` (after its `    return save(data)`, before `def main`):

```python


def cmd_set_global_settings(text):
    update, error = parse_settings(text, "global setting", GLOBAL_SETTINGS_VALID, GLOBAL_SETTINGS_REFUSALS)
    if update is None:
        return emit({"ok": False, "error": error}, 2)
    data = load()
    settings = data.get("global_settings")
    if not isinstance(settings, dict):
        settings = data["global_settings"] = {}
    settings.update(update)
    return save(data)
```

- [ ] **Step 8: Route the command in `main`**

In `main`, insert directly after the `get-global-settings` branch added in Task 1:

```python
    if argv[:1] == ["set-global-settings"] and len(argv) == 2:
        return cmd_set_global_settings(argv[1])
```

(No `and argv[1]` guard: `set-global-settings ""` must reach the JSON parse and be refused as not valid JSON, not as usage.)

- [ ] **Step 9: Extend the docstring with the setter contract**

In the module docstring, replace:

```
or a damaged value, just means the default); `set-project` and `set-run-settings`
write atomically and keep any other keys already in the file. Run settings live
under "run_settings", keyed by the root path verbatim. There are seven, each read
on its own:
```

with:

```
or a damaged value, just means the default); `set-project`, `set-run-settings` and
`set-global-settings` write atomically and keep any other keys already in the file.
Run settings live under "run_settings", keyed by the root path verbatim. There are
seven, each read on its own:
```

and replace the closing lines:

```
Global settings live under "global_settings". There is one, notifyOnEscalation,
a boolean; when no boolean is stored, `get-global-settings` answers true when any
project's stored run-settings notifyOnEscalation is true, else false.
"""
```

with:

```
Global settings live under "global_settings". There is one, notifyOnEscalation,
a boolean; when no boolean is stored, `get-global-settings` answers true when any
project's stored run-settings notifyOnEscalation is true, else false.
`set-global-settings` takes a JSON object, validates every key before writing
anything, and changes only the keys given, keeping any other keys under
"global_settings".
"""
```

- [ ] **Step 10: Run the tests to verify they pass**

Run: `uv run --with pytest python3 -m pytest tests/core/backend/projects/test_viewer_state.py -q`

Expected: PASS, every test.

- [ ] **Step 11: Run the full gate**

Run: `timeout 600 bash tests/run.sh`

Expected: pytest reports all passed (including `tests/architecture`), every QML test prints `Totals: ... 0 failed`, exit 0.

- [ ] **Step 12: Commit**

```bash
git add core/backend/projects/viewer-state.py tests/core/backend/projects/test_viewer_state.py
git commit -m "feat(viewer-state): set-global-settings through a shared settings parser"
```

---

## Self-Review

**Spec coverage** (spec "Tests" numbering → test):

| # | test | task |
|---|---|---|
| 1 | `test_get_global_settings_with_no_file_is_false` | 1 |
| 2 | `test_get_global_settings_writes_nothing` | 1 |
| 3 | `test_get_global_settings_treats_bad_files_as_false` | 1 |
| 4 | `test_migration_read_is_true_when_any_project_is_true` (first/last) | 1 |
| 5 | `test_migration_read_is_false_when_no_project_is_true` | 1 |
| 6 | `test_migration_read_counts_only_the_boolean_true` | 1 |
| 7 | `test_migration_read_with_damaged_run_settings_is_false`, `test_migration_read_skips_damaged_entries` | 1 |
| 8 | `test_damaged_global_settings_fall_through_to_the_migration_read` | 1 |
| 9 | `test_migration_read_uses_the_legacy_file` | 1 |
| 10 | `test_stored_global_value_wins_over_the_migration_read` | 1 |
| 11 | `test_get_global_settings_prints_only_notify_on_escalation` | 1 |
| 12 | `test_set_then_get_global_settings_round_trips` | 2 |
| 13 | `test_set_global_false_sticks_while_a_project_is_true` | 2 |
| 14 | `test_set_global_settings_empty_object_is_accepted` | 2 |
| 15 | `test_set_global_settings_preserves_other_keys` | 2 |
| 16 | `test_set_global_settings_replaces_a_damaged_global_settings` | 2 |
| 17 | `test_set_global_settings_keeps_keys_it_was_not_given` | 2 |
| 18 | `test_set_global_settings_carries_legacy_state_forward` | 2 |
| 19 | `test_set_global_settings_replaces_a_corrupt_file` | 2 |
| 20 | `test_set_global_settings_leaves_no_temp_files_and_a_private_file` | 2 |
| 21 | `test_set_global_settings_unwritable_directory_fails_cleanly` | 2 |
| 22 | `test_other_setters_keep_the_stored_global_settings` | 2 |
| 23 | `test_set_global_settings_refusal_is_exact_and_creates_nothing` | 2 |
| 24 | `test_set_global_settings_refusal_leaves_the_file_untouched` | 2 |
| 25 | `test_set_global_settings_reports_the_first_bad_key_in_input_order`, `test_set_global_settings_duplicate_key_last_wins` | 2 |
| 26 | `test_global_settings_bad_usage_is_rejected` | 1 |

USAGE string: Task 1 Steps 1 and 4. Docstring (six commands, summary line, global contract): Task 1 Step 8 and Task 2 Step 9. Reuse of `valid_boolean` and the existing sentence: Task 2 Step 6. Existing commands unchanged: only `parse_run_settings` is renamed and parameterised (Task 2 Steps 3-5) and `load()` additionally catches `RecursionError` (Task 1 Step 5), which turns a traceback into the documented "corrupt file means the default" for every getter.

**Placeholder scan:** none.

**Type consistency:** `parse_settings(text, noun, valid, refusals)` is defined in Task 2 Step 3 and called with that order in Steps 4 and 7; `get_global`, `GLOBAL_TRUE`, `GLOBAL_FALSE`, `legacy_file` are defined in Task 1 Step 2 and used in Task 2 Step 1; `same_json` and `DEFAULTS` already exist in the test file.

**Review Focus:** each of the five lines has its test in the owning task (Task 1: nested file, unreadable file, new-wins-over-legacy, damaged-global-with-no-true; Task 2: nested / huge-integer / non-ASCII-key refusals).
<!-- task-pipeline: validated -->
