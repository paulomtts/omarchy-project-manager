# 1.2 runs-alerts.py: escalations from the journal (card a65dfeb3)

Narrowed from `docs/superpowers/specs/2026-10-05-alerts-panel-closed-design.md` (below "the
parent"): Behaviour, "What alerts" (lines 88-91); Architecture, the `runs-alerts.py` bullet
(lines 134-145); Failure modes (lines 175-183); Testing, the `test_runs_alerts.py` bullet
(lines 192-199). Parent story 11ef73c2. Blocked by 54739fc3 (1.1 `alertNotification`,
already landed in `core/domain/runs.js`; this card does not use it).

**The card overrides the parent where they differ.** The parent describes a later design: a
cursor argument, `--since-seq`, `am events --escalations`, a hello that must carry `head`,
an `am runs --all-projects` seed, `dead` detection, `{"cursor": N}` lines and a `gseq` in
the alert (parent lines 101-127, 134-145). None of that is in this card. This card's helper
takes no argument, follows `am watch --all --follow --from-now` (the command the parent
measured, line 65), accepts hello schema 1 or 2 with or without `head`, and alerts
`escalated` only.

## Starting point

- `core/backend/runs/runs-alerts.py` and `tests/core/backend/runs/test_runs_alerts.py` do
  not exist. Create both.
- `core/backend/runs/runs-watch.py` is the model: a long-lived helper that spawns `am watch`,
  pumps its stdout through a reader thread into a queue, collects stderr on a second thread,
  checks hello lines, treats any line with an `ok` key as am's refusal envelope, and maps
  am's exit (`finish`) to the helper's last line. Its signal handling (`guarded`,
  `quiet_exit`, `stop`) is the pattern to copy. `tests/core/backend/runs/test_runs_watch.py`
  is the model for the test scaffolding (fake `am` replaying a `script.json`, `world`
  fixture, `env_for`).
- `core/backend/common/json_line.py` provides `emit`. Import it as runs-watch.py does
  (`sys.path.insert(0, <this dir>/..)`, `from common.json_line import emit`).
- `brd projects` prints `{"ok": true, "data": [{"id", "name", "root_path", "created_at"},
  ...]}` (verified on this machine).
- Fixtures: `tests/fixtures/am/watch-hello.json` (`schema_1`: no `head`; `schema_2`: `head`,
  `store_id`, `cursor_reset`), `tests/fixtures/am/watch-events.json` (`data.events[]`, whose
  `run_upsert` lines carry `payload.status` `started` and `payload.repo_dir`
  `/home/user/Code/omarchy-project-manager`). No captured line is `escalated`.

## Constraints

- Layering (`docs/architecture.md`, enforced by `tests/architecture/test_layers.py`): files
  under `core/backend/` are not `.qml`/`.js`; no second definition of a shared Python helper
  (`def emit(`, `def inside(`, `write_atomic(`, `split_frontmatter(`, `frontmatter_of(`) —
  `test_shared_python_helpers_are_defined_once`. `tests/architecture` must pass unchanged.
- Parent line 145: only documented `am` and `brd` commands, as argv lists, never a shell.
  am's database and on-disk layout are never read.
- Card: docstrings and comments state the contract only, no narrative. TDD: tests first.
- Verification: `bash tests/run.sh` green. Quick loop:
  `uv run --with pytest python3 -m pytest tests/core/backend/runs/test_runs_alerts.py tests/architecture -q`.
- Never `pkill`/`killall`/pattern kills in tests or tooling; signal only recorded PIDs; bound
  every wait with a timeout.

## Behaviour

### Invocation

`runs-alerts.py` takes no argument. Any argument at all is a `Usage` error:
`{"ok": false, "error": {"type": "Usage", "message": "usage: runs-alerts.py"}}`, exit 2; neither
`am` nor `brd` is looked up or run. (The card lists no `Usage`; this is the sibling helpers'
convention for argv the contract does not allow.)

### Start order

1. `am` is looked up on `PATH` (`shutil.which("am")`). Not found: `AmMissing` envelope
   (`"am is not installed."`), exit 1; `brd` is not run.
2. The registry is read (below).
3. `am` is spawned with argv exactly `[<am>, "watch", "--all", "--follow", "--from-now"]`,
   stdin `/dev/null`, stdout and stderr piped, UTF-8 with replacement for bad bytes.

### The registry

Read by running `brd projects` (argv list, stdin `/dev/null`, 30 s timeout) at start, and
again each time an escalation transition (below) names a `repo_dir` that is not in the
current registry. It is never read at any other time.

- A successful read is: brd exits 0 and prints a JSON object with `ok` true and a list
  `data`. Each entry that is an object with a non-empty string `root_path` and a string
  `name` registers `realpath(root_path)` → (`root_path` as printed, `name`). Other entries
  are skipped, as is one whose `root_path` `realpath` cannot take (an embedded NUL raises
  `ValueError`; it must not end the helper). When two entries share a realpath, the first wins. A successful read
  **replaces** the registry.
- Anything else — `brd` not on `PATH`, non-zero exit, timeout, output that is not that JSON
  shape — is a failed read. A failed read **keeps** the registry as it was (empty at start).
  It prints nothing and does not end the helper (parent line 183: "no registered root is
  known; nothing alerts; retried at the next candidate").

### The stream

Each line am prints is handled in order, as it arrives; nothing is batched or delayed.

- **Not JSON, or not a JSON object:** ignored.
- **A line with an `ok` key:** am's refusal envelope; remembered (the last one wins) for the
  end, otherwise ignored.
- **A hello** (`event == "watch"`): every hello is checked. `schema` must be an integer
  (a JSON `true`/`false` is not) equal to 1 or 2; otherwise `SchemaMismatch` envelope, exit 1,
  am stopped. The message names the schema received, e.g.
  `am watch speaks schema 3; this helper reads schema 1 or 2.` `head` and every other hello
  key are neither required nor read. A hello prints nothing.
- **A `run_upsert`** (`event == "run_upsert"`, `run_id` a non-empty string, `payload` an
  object) **after the first hello**: updates the run's state. Every other line, including a
  `run_upsert` before any hello, is ignored. `gseq` is not required (schema 1 has none).

### Per-run state and the alert

For each `run_id` the helper keeps the last `status` and the last `repo_dir` it saw:

- `payload.status`, when a string, becomes the run's last status; otherwise the last status
  is unchanged.
- `payload.repo_dir`, when a non-empty string, becomes the run's last repo_dir; otherwise
  it is unchanged.

A **transition into escalated** is a `run_upsert` whose `payload.status` is the string
`"escalated"` while the run's previous last status was anything else (another string, or
none: a run first seen escalated is a transition, since `--from-now` means everything seen
is new). The state is updated before deciding, and the transition is decided against the
status held before this line.

On a transition, with the run's (updated) last repo_dir:

1. No repo_dir known: nothing printed.
2. `realpath(repo_dir)` in the registry: alert.
3. Not in the registry: the registry is read again; then alert if it is now registered,
   else nothing printed. (A `repo_dir` realpath cannot take — an embedded NUL — is never
   registered and triggers no read.)

The alert is one line, flushed at once, key order as shown:

```json
{"alert": {"run_id": "<run_id>", "root": "<root_path as brd printed it>", "project": "<name>", "state": "escalated"}}
```

So: consecutive `escalated` upserts of a run print once; a run seen `started` (or any other
status) after its escalation and then `escalated` again prints again (parent line 90-91:
"a run that is resumed and escalates again alerts again"); runs of unregistered repos print
nothing; a run whose project is registered while the helper runs alerts at its next
transition. Nothing other than alert lines and the final envelope is ever printed.

### Ending

| how it ends | last line | exit |
|---|---|---|
| any argument | `Usage` | 2 |
| `am` not on `PATH` | `AmMissing` | 1 |
| a hello with schema not 1 or 2 | `SchemaMismatch` | 1 |
| am exits 0, no refusal envelope | none | 0 |
| am exits 3 with a refusal envelope of type `StoreBusyError` | that envelope, unchanged | 1 |
| am exits 3 otherwise | `CorruptJournal`; message from the envelope's `error.message` when a non-empty string, else am's stderr, else `am watch exited 3.` | 1 |
| am exits non-zero other than 3 with a refusal envelope | that envelope, unchanged | 1 |
| am exits non-zero other than 3, no envelope | `HelperError`; am's stderr, else `am watch exited <code>.` | 1 |
| am exits 0 having printed a refusal envelope | that envelope, unchanged | 1 |
| SIGTERM or SIGINT | none | 0 |
| stdout closed (broken pipe) | none | 0 |
| any other unexpected exception | `HelperError`, `The runs alerts failed: <reason>` | 1 |

(The am-exit rows are runs-watch.py's `finish` unchanged.) Every envelope is
`{"ok": false, "error": {"type": T, "message": M}}` on one flushed line. On every path that
ends while am still runs, am is terminated (killed after 2 s) and reaped; am is never left
behind.

## Out of scope

- Everything the parent adds beyond the card: cursor argument and `{"cursor": N}` lines,
  `--since-seq`, `am events --escalations`, `head` requirement, `cursor_reset`/`store_id`
  handling, the `am runs --all-projects` seed, `dead` detection and its poll, `gseq` in the
  alert line, `--all-projects` spelling, terminal-status handling for cancel spellings.
- Sibling cards: `core/stores/RunAlertsService.qml`, the manifest `service` kind and entry
  points, `RunAlertsStore` dropping `notify.py`, the Runs screen switch label and caption,
  `docs/architecture.md` entries, `install.sh`. No file outside the two named here changes.
- Calling `notify.py`, reading `get-global-settings`, taking a run snapshot: the service's
  job.

## Tests

All in `tests/core/backend/runs/test_runs_alerts.py`. **Tier: hermetic Python
subprocess tests (pytest)** — the deliverable is a standalone executable whose contract is
its argv, stdout lines and exit code against external `am` and `brd`, so each test runs the
real script with `subprocess.Popen` against fake `am` and `brd` executables on a temp `PATH`
(`<tmp>/bin:/usr/bin:/bin`), temp `HOME` and `XDG_*`. No real `am`/`brd`, no network.
Every wait has a timeout.

Scaffolding, copied (not imported) from `test_runs_watch.py`:

- `FAKE_AM`: replays `$FAKE_AM_DIR/script.json` steps (`line` object, `raw` text, `sleep`
  seconds), then writes `stderr` and exits with `exit`; appends its argv to `calls.log` and
  writes its pid; an option to block forever after the steps (for signal tests).
- `FAKE_BRD`: appends each call's argv to a log; answers the Nth call from
  `responses[N]` (the last one repeats): `stdout` text, `exit` code; a missing `brd` is
  simply not installed.
- Lines from fixtures are built from `watch-hello.json` and a copy of a captured
  `run_upsert` from `watch-events.json` with `payload.status`/`repo_dir` edited; such
  edited and hand-made lines are labelled `synthetic:` in a comment, as test_runs_watch.py
  does.

Cases (each one test unless noted):

1. **argv:** am is called with exactly `watch --all --follow --from-now` (asserts
   `--from-now` present).
2. **no backlog alert:** a registered `run_upsert` `escalated` before the hello prints
   nothing; the same run escalating after the hello alerts once.
3. **hello accepted:** schema 1 fixture and schema 2 fixture each followed by an escalation
   of a registered run alert (parametrised).
4. **hello refused:** schema 3, missing, `"2"` string, `true` each give `SchemaMismatch`,
   exit 1, no alert (parametrised); a second hello with schema 3 after a good one also
   refuses.
5. **alert line:** exact JSON object and key set; `root` is `root_path` as brd printed it,
   `project` is `name`; matched by realpath (registry root given through a symlink).
6. **no duplicate:** three consecutive `escalated` upserts of one run print one alert.
7. **re-alert:** `escalated`, `started`, `escalated` prints two alerts.
8. **repo_dir carried:** `started` with repo_dir, then `escalated` without repo_dir alerts.
9. **unregistered ignored:** an escalation of an unregistered repo prints nothing; brd is
   called twice (start + one re-read).
10. **root learned:** brd's first answer lacks the root, its second has it; the escalation
    alerts and brd was called exactly twice.
11. **registered root does not re-read:** an escalation of a registered root leaves brd at
    one call; non-escalated upserts of unknown repos never call brd again.
12. **brd failing:** brd missing / exit 1 / garbage stdout at start: the helper keeps
    running, prints no alert for a registered-elsewhere repo, ends with exit 0 when am exits
    0 (parametrised); a failed re-read keeps the earlier registry (second answer exit 1,
    a registered run still alerts afterwards).
13. **AmMissing:** no `am` on `PATH`: `AmMissing`, exit 1, brd never called.
14. **Usage:** any argument gives `Usage`, exit 2, neither am nor brd called.
15. **am exit 0:** no envelope, exit 0.
16. **CorruptJournal:** am exit 3 with stderr; and with a refusal envelope (its message).
17. **StoreBusyError:** am exit 3 with a `StoreBusyError` envelope re-emits it, exit 1.
18. **HelperError:** am exit 2 with stderr, no envelope: `HelperError` with that stderr.
19. **signals:** SIGTERM and SIGINT to the helper (its own Popen pid) while fake am blocks:
    exit 0, no envelope, the recorded fake-am pid is gone afterwards (parametrised).
20. **ignored lines:** non-JSON text, a JSON array, a `run_upsert` with empty `run_id` or a
    non-object payload, other event kinds: no alert, no crash.
21. **flushed at once:** with fake am sleeping after an escalation, the alert line is read
    before am exits.

`tests/architecture` must still pass with the new file in place (no duplicated shared
helper).
