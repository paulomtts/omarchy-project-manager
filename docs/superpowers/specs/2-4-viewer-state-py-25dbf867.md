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
