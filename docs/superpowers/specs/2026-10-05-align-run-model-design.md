# Align the run model with real am — design

Status: proposed. Fixes merged code from S1 (`2026-10-03-am-run-monitor-design.md`)
and S2 (`2026-10-03-am-run-controls-design.md`). Queue position: first milestone
after S3 (`2026-10-03-am-run-dispatch-design.md`), before "Dispatch at story
level". Every later run milestone assumes it has landed.

## Problem

On every real run the monitor shows progress `0/0`, no current phase, an empty
subtask tree in Run detail, no default attempt (the output pane never loads), no
subtask marks on the Board and the Graph, and zero rollups. The S1 domain model
was written against a guessed `am status` shape: hand-written fixtures in that
guessed shape made the tests pass, and the contract test
(`tests/contract/test_am_shapes.py`) never pinned an `am status` of an existing
run.

### What real am prints (verified 2026-10-05, am 0.1.0)

`am status RUN --repo-dir R` data has exactly the keys `run`, `stories`, `rows`,
`control`, `integrity`. There is **no top-level `subtasks`**.

- `run`: `id, workflow, repo_dir, base_branch, branch_prefix, status, started_at`
  (no `milestone_id`: only `am runs` carries it).
- `stories[]`: `card_id, title, level, status, tip_branch, subtasks[]`; each
  subtask is an object `card_id, branch, base_branch, status, worktree_path,
  phases[]`.
- `phases[]`: `name, kind (agent|deterministic), status, started_at, ended_at,
  detail, attempts[]`. Phases are recorded as they are reached (a pending subtask
  has `[]`); deterministic phases never have attempts.
- `attempts[]`: `n, status, dispatch, exit_code, duration, prompt_path,
  result_path, stdout_path`. The number is `n`.
- `rows[]`: `story, subtask, phase, attempt, state`, one row **per attempt** (a
  phase without attempts gets one row with `attempt: null`), in tree order. A
  finished 10-subtask milestone has 140 rows. `state` is the attempt's status on
  an attempt row, the phase's status otherwise.
- Status values. Run, story, subtask and phase: `pending, started, done, failed,
  escalated, stopped, cancelled`. Attempt: `started, ok, schema_invalid,
  gate_failed, harness_error`.
- Synthetic stories. `integrate` (title `Integrate`) holds one resolver subtask
  per conflicting story **whose `card_id` is that real story's id** (verified in
  `status-done-integrate.json`); `bases` holds `base-<story id>` subtasks. A run
  that escalates at the final Integrate verification has **no failed phase in the
  tree at all** (`status-escalated-integrate.json`).
- `control`: `lease` (`pid, host, heartbeat_at, accepting, live, acquired_at`) or
  null, `requests[]` (`handled_at` null until handled), `claims[]`.
- Times look like `2026-10-05 02:14:00.590972+00:00` (space, not `T`); QML's
  `Date.parse` reads them (checked under qmltestrunner, Qt 6.11).

`am runs --repo-dir R` rows: the seven identity fields plus `milestone_id`,
`card_id` (set for a `--card` run only), `lease` (`pid, host, heartbeat_at,
accepting, live`, or null) and `progress` (`stories {done,total}`,
`subtasks {done,total}`, `current {card, phase, attempt}` or null).

`am logs RUN CARD --phase P --attempt N --repo-dir R` data: `run_id, story_id,
card, phase, attempt, status, exit_code, artifacts`, with `artifacts.prompt`,
`.result`, `.stdout`, `.stderr` each `{path, present, text}` (`text` null when
absent). **There is no `data.stdout` string.** `--repo-dir` defaults to `.`;
without it, from any other directory, am refuses with `UnknownRunError` (checked
from `$HOME`, which is the shell process's cwd).

`am watch --follow` prints first `{"event":"watch","schema":1,"am":"0.1.0",
"runs_dir":…}`; `--from-now` exists. `am watch RUN` (no `--follow`) is one
envelope `{"data":{"events":[…]}}` of journal lines `seq, ts, run_id, event,
story, card, phase, attempt, payload`.

### Reproduction

```
python3 core/backend/runs/runs-snapshot.py ~/Code/omarchy-project-manager > snap.json
grep -v '^\.pragma\|^\.import' core/domain/runs.js > runs-node.js
# node: eval runs-node.js; for each snap.runs[i]: run = normalizeRun({row: <entry without status>, status: entry.status})
```

Output on 2026-10-05 for both runs of this repo (`20261005T021400Z-837c4431`
live, `20261004T204141Z-cb11063d` done):

```
tree.stories 4  tree.subtasks 0  rows 40 / 140
runProgress {done:0,total:0}   currentPhase ""
runTree: 4 stories, 0 subtasks each      defaultAttempt null
rollup(milestone) all 0                  cardRunState(subtask) state "none"
runsTouching(subtask) 0                  attemptStatus(subtask, "explore", 1) ""
escalationReason "escalated at review"   (last row's phase, not the failure)
glyphStateOf("ok"|"gate_failed"|"canceled") ""      runState({status:"canceled"}) "unknown"
logTail(<real am logs data>) {text:"", truncated:false}
```

### Every consumer of the wrong shape (file:line on `main` at cbe313c)

| where | reads | real-data symptom |
|---|---|---|
| `core/domain/runs.js:66-67` `normalizeRun` | `st.subtasks` (absent), passes `st.rows` through unrenamed | `tree.subtasks` always `[]`; rows keyed `story/subtask/state` |
| `runs.js:118-123` `_touches` | `tree.subtasks[].card_id` | a run never touches a subtask card |
| `runs.js:160-181` `cardRunState` (`:168`) | `tree.subtasks` | subtask cards: state `none`, no phase/attempt |
| `runs.js:186-194` `runsTouching` | via `_touches` | card detail of a subtask lists no runs |
| `runs.js:219-243` `rollup` (`:232`, `:233`, `:239`) | `rows[].card_id`, `tree.subtasks`, `rows[].status`; counts rows | zero rollups; with renamed keys it would count attempts (140), not subtasks (10) |
| `runs.js:265-288` `escalationReason` (`:266`, `:283-285`) | `tree.subtasks`; fallback takes the LAST row's phase whatever its state | no detail; "escalated at mark_done" for an Integrate escalation |
| `runs.js:309` `_subtasksOf` | `tree.subtasks` | feeds the four below |
| `runs.js:326-338` `runProgress` | `_subtasksOf`; done = "every recorded phase done" | `0/0`; once fixed, a subtask between two phases would count as done (phases are recorded as reached) |
| `runs.js:341-352` `currentPhase` | `_subtasksOf` | no current phase |
| `runs.js:464-472` `glyphStateOf` | knows `done/started/failed/…`, not attempt outcomes `ok/gate_failed/schema_invalid/harness_error`, not `canceled` | attempt rows in Run detail have no glyph; failures not urgent |
| `runs.js:438-446` `logTail` | `data.stdout`, `data.stderr` as strings | the output pane is empty even for a loaded attempt |
| `runs.js:502-508` `_lastRowStatus` | `rows[].card_id`, `rows[].status` | status fallback of tree nodes never matches |
| `runs.js:519-544` `_subtaskNode` | opens on the first started phase else the LAST phase | a finished subtask opens on `mark_done.0` (deterministic, no attempt): clicking it does nothing, its attempts never expand |
| `runs.js:551-597` `runTree` (`:553`, `:576`) | `tree.subtasks`, `rows[].card_id` | empty tree |
| `runs.js:603-626` `defaultAttempt` (`:605`, `:619`) | `_subtasksOf`, `rows[].card_id` | null: the output pane never loads |
| `runs.js:629-637` `attemptStatus` | `_subtasksOf` | `logsStatus` always `""` |
| `runs.js:76-86` `runState`, `:678` `controls` | `cancelled` only | a `canceled` run is `unknown` |
| `core/stores/RunStore.qml:328`, `:362` | `attemptStatus` | no re-fetch when the selected attempt moves |
| `RunStore.qml:347` | `defaultAttempt` | no attempt opened when a run is selected |
| `RunStore.qml:330` + `core/backend/runs/runs-logs.py:44-48` | `am logs` argv without `--repo-dir` | every logs fetch from the panel is `UnknownRunError` |
| `RunStore.qml:380` | `logTail` | empty pane |
| `RunStore.qml:439` | `normalizeRun` | the empty tree enters the store |
| `ui/screens/RunsScreen.qml:169` | `runProgress` | `0/0` |
| `RunsScreen.qml:229` | `currentPhase` | blank |
| `RunsScreen.qml:256` | `escalationReason` | generic text |
| `RunsScreen.qml:151` | hardcoded `am · schema 1` | wrong once am announces schema 2 |
| `ui/screens/RunDetailScreen.qml:34` | `runTree` | stories with no subtasks |
| `RunDetailScreen.qml:87`, `:90` | `glyphStateOf` | no glyph / not urgent for attempt outcomes |
| `RunDetailScreen.qml:214` | `escalationReason` | generic text |
| `RunDetailScreen.qml:364-365` | `currentPhase/currentAttempt` of a tree node | a finished subtask cannot be opened |
| `RunDetailScreen.qml:387` | `PhaseTimeline` phases from the tree | no timeline |
| `ui/screens/CardDetailScreen.qml:38` | `runsTouching` | no runs on a subtask card |
| `CardDetailScreen.qml:243` | `currentPhase` | blank |
| `ui/screens/BoardScreen.qml:79-80` | `cardRunState`, `rollup` | no subtask marks, zero rollups |
| `ui/screens/GraphScreen.qml:52-58` | `cardRunState`, `rollup` (and the pip ring) | no marks, no ringed pip |
| `core/backend/runs/runs-snapshot.py:33` | `TERMINAL` without `canceled` | a `canceled` run is treated as live and is never capped |
| `core/backend/runs/runs-watch.py:121-125` | hello schema must be 1 | schema 2 ends the watch with `SchemaMismatch` |
| `tests/contract/test_am_shapes.py` | pins `runs` of an empty project, an unknown-run `status`, `watch`; `:159` hello `== 1` | never pinned `status`, a `runs` row or `logs` |
| `tests/core/domain/tst_runs.qml:15-30` `fullRaw` | hand-written status with top-level `subtasks` | hid the defect |
| `tests/core/stores/tst_run_store.qml:917-918`, `:925`, `:1087-1088`, `:1180`; `tests/ui/tst_runs_flow.qml:185`, `:201` | hand-written top-level `subtasks`, `data.stdout` strings | hid the defect |
| `tests/core/backend/runs/test_runs_snapshot.py:102-106`, `test_runs_logs.py:47-53` | hand-written am payloads | same |

Fine as they are: `runTitle` (returns the milestone id by S1 design; titles are
the "Run history and titles" milestone), `shortId`, `attention`,
`runFilterCounts`, `filterRuns`, `searchRuns` (through the fixed helpers),
`newAlerts` (through `runState` and `escalationReason`), `controls` (through
`runState`), `Navigator.qml:47`, `Panel.qml:312`, `Panel.qml:677`.

## Decisions

1. **Keep the flat normalized shape.** Downstream code (and every queued
   milestone) reads `tree.stories[]`, `tree.subtasks[]` and `rows[]` keyed by
   `card_id`; the real tree flattens without loss once each subtask carries its
   story id. Evidence against flat is limited to the synthetic stories, handled
   by rule 2.
2. **Synthetic stories stay out of the subtask list.** A subtask under
   `integrate` or `bases` is not put in `tree.subtasks` (an Integrate resolver's
   card id is a real story's id; a `base-*` id is no card). Rows under a
   synthetic story whose subtask id is a real card id (Integrate resolvers) are
   dropped; rows of `base-*` subtasks are kept (Run detail labels them). The
   synthetic stories themselves stay in `tree.stories` (Run detail shows them as
   labelled rows).
3. **Rows stay per attempt; nothing counts them as subtasks.** `rollup` counts
   each real subtask of the winning run once, by the subtask's own `status`.
   `runProgress` counts real subtasks and those whose own status is `done`.
   The plugin's total leaves Integrate resolvers out, so it can be lower than
   `am runs`' `progress.subtasks.total` (am counts them; its docstring says so).
4. **A subtask opens on an attempt that exists.** A tree node's current phase is
   its first `started` phase, else its last phase with a numbered attempt (am
   logs' own default), else its last phase.
5. **The escalation fallback names a failure only.** After the failed phase's
   detail, `escalationReason` names the phase of the last row whose status is
   `failed`, `escalated`, `gate_failed`, `schema_invalid` or `harness_error`;
   none gives `escalated`.
6. **Attempt outcomes have glyphs.** `glyphStateOf`: `ok` is `done`;
   `gate_failed`, `schema_invalid`, `harness_error` are `dead`.
7. **The output pane reads am logs' artifacts** (`artifacts.stdout.text`, then
   `artifacts.stderr.text`; a null `text` is no lines), and `runs-logs.py`
   takes the project root first and passes `--repo-dir`.
8. **Both cancel spellings, both hello schemas.** See below.
9. **Keep the `am status` fan-out.** `am runs` now has `milestone_id`, `lease`
   and progress counts, but no story/subtask membership, phases or attempts:
   card marks, rollups, Run detail and escalation reasons all need `am status`.
   "Runs: a global destination" moves this fan-out unchanged.
10. **Keep the backlog filter in `runs-watch.py`.** It is correct (the helper
    drops lines older than its own start); switching to `--from-now` is a cost
    change, not a correctness one, and `runs-watch.py` is rewritten for several
    roots by "Runs: a global destination".

## Target normalized run (`Runs.normalizeRun` output)

Keys and types unchanged except where marked **new**:

```
{ id, repo_dir, milestone_id, status, started_at, base_branch, branch_prefix, workflow,   // strings; status as am spells it
  lease: {pid, host, heartbeat_at, accepting, live} | null,
  requests: [{command, requested_at, handled_at}],
  tree: {
    stories:  [{ card_id, title, level, status, tip_branch,           // am's fields as given
                 subtasks: [<card_id string>, ...] }],                 // ids, every story incl. synthetic
    subtasks: [{ card_id, branch, base_branch, status, worktree_path,
                 phases: [{ name, kind, status, detail, started_at, ended_at,
                            attempts: [{ n, status, ... }] }],         // as am gives them
                 story_id }]                                          // **new**: owning story; real stories only, am's order
  },
  rows: [{ story_id, card_id, phase, attempt, status }]               // am's story, subtask, phase, attempt, state; resolver rows dropped
}
```

Copies, never am's objects. Anything missing or malformed becomes its default,
as today. `milestone_id` keeps coming from the `am runs` row.

### Expected values on the fixtures (the acceptance numbers)

Each run is `normalizeRun({row: <its am runs entry without status>, status:
<fixture>.data})`; the entry is in `runs.json` or, for the e2e fixtures, in the
fixture's `_am_runs_row`.

| fixture | state | stories / subtasks / rows | runProgress | currentPhase | defaultAttempt | rollup(milestone) r/p/e/d/pend/total |
|---|---|---|---|---|---|---|
| `status-started.json` | running | 4 / 8 / 44 | 3/8 | `explore` | `299ec9c0… explore 1` | 1/0/0/3/4/8 |
| `status-done.json` | done | 4 / 10 / 140 | 10/10 | `""` | `22153f5f… review 1` | 0/0/0/10/0/10 |
| `status-escalated.json` | escalated | 3 / 4 / 40 | 2/4 | `""` | `eb8b1851… review 1` | 0/0/1/2/1/4 |
| `status-escalated-integrate.json` | escalated | 2 / 2 / 28 | 2/2 | `""` | `0e01b1ba… review 1` | 0/0/0/2/0/2 |
| `status-done-integrate.json` | done | 3 / 2 / 28 of 30 | 2/2 | `""` | `5d5114f9… review 1` | 0/0/0/2/0/2 |

More, all from the same fixtures: `escalationReason` of `status-escalated.json`
is its review phase's `detail` (`phase 'review' gate 'review_blockers_gate'
failed: …`), of `status-escalated-integrate.json` is `escalated`;
`cardRunState(runs, "299ec9c0…")` on the started run is `running`, phase
`explore`, attempt 1; on the escalated run `eb8b1851…` is `escalated`, dimmed,
`review`, 1; `runTree` of `status-done.json` has stories of 2, 3, 1 and 4
subtasks, each node `done`, current `review.1`, 7 attempts, 14 phases; `runTree`
of `status-done-integrate.json` has one synthetic `Integrate` entry, status
`done`, and no `Other` group; `logTail(logs-attempt.json data)` is the 19 lines
of `artifacts.stdout.text` (stderr `text` is null: no lines), not truncated. These numbers were produced by a
prototype of decisions 1-5 run under node on the committed fixtures.

## Fixtures

Real captured `am` payloads in `tests/fixtures/am/`, committed with this spec
because two of them cannot be captured on demand (the only started run of this
repo finishes before this milestone runs; no real run of any project has ever
escalated). Pretty-printed with sorted keys; only `/home/<user>` paths are
rewritten to `/home/user`.

| file | source |
|---|---|
| `runs.json` | `am runs --repo-dir ~/Code/omarchy-project-manager`: one live `started` run (lease live), one `done` |
| `status-started.json` | `am status 20261005T021400Z-837c4431` (live, mid-run) |
| `status-done.json` | `am status 20261004T204141Z-cb11063d` (S2's finished run) |
| `status-escalated.json` | the installed am's `status` serializer for a run of agent-manager's e2e suite under its fake claude (subtask escalated at review, gate detail); `_note` says so; `_am_runs_row` is its real `am runs` entry |
| `status-escalated-integrate.json` | same capture method: escalated at the final Integrate verification, no failed phase in the tree |
| `status-done-integrate.json` | same capture method: a resolved conflict, synthetic `integrate` story whose resolver subtask id is a real story id |
| `watch-events.json` | `am watch 20261004T204141Z-cb11063d`, truncated to its first 60 of 474 events (`_note`) |
| `watch-hello.json` | `{_note, schema_1, schema_2}`: the real hello line of `am watch … --follow --from-now`, and a DERIVED copy with `schema: 2` |
| `logs-attempt.json` | `am logs 20261004T204141Z-cb11063d adff6c85… --phase review --attempt 1 --repo-dir …` |

Readers ignore keys starting with `_`. The e2e captures used a pytest plugin
loaded into agent-manager's own suite (`uv run pytest -p capplug -m e2e_fake
<test>`) that, after the test body, wrote `cli.render(cli.ok_envelope(
cli.status_for(run_id, repo_dir=root)))` for every run of the test's repo, which
is byte-for-byte what `am status` prints.

**Rule.** Every unit test of code that reads `am` output (`normalizeRun`,
`logTail`, the `runs-*` helpers and `run-control.py`, `RunStore`'s snapshot,
logs and watch handling) builds its input from these fixtures. A hand-written
am payload is allowed only for a synthetic edge case (garbage, a missing key, a
value no capture contains) and carries a `synthetic:` comment saying what it
stands for. Tests of code that takes a normalized run (screens, components,
`runs.js` helpers past `normalizeRun`) may keep building normalized runs by
hand: that shape is the plugin's own and does not change here; a test that
asserts behaviour on real data normalizes a fixture instead. Edits to a fixture
inside a test (a status set to `canceled`, a `ts` stamped `NOW`) are made on a
fresh copy, are labelled, and never change the shape.

**Loading.** Python reads them with `json.load`. QML tests use
`tests/helpers/amFixtures.js` (`.pragma library`): `load(name)` returns a fresh
parse of `tests/fixtures/am/<name>` through a synchronous `XMLHttpRequest`
(resolved with `Qt.resolvedUrl` against the helper itself) and throws an Error
naming the file when it cannot. `tests/run.sh` sets `QML_XHR_ALLOW_FILE_READ=1`
for `qmltestrunner`, without which Qt refuses `file://` reads (verified).

**Contract.** `tests/contract/test_am_fixtures.py` pins the fixtures' key sets at
every level (runs row, lease, progress; status data, run, story, subtask, phase,
attempt, row, control; logs data and each artifact; watch event; hello), the
status vocabularies above, and that status data has no top-level `subtasks`.
When `am` is installed and the plugin's main checkout (the parent of `git
rev-parse --git-common-dir`; a worktree has no am projection of its own) has a
run, it also runs `am runs` and `am status <newest>` there, read-only, and
checks the same key sets, so a changed `am` fails here first. `--repo-dir` is
the only option it passes; it never writes.

## Both spellings, both schemas

A later `am` migration respells the run status `canceled` and announces it with
hello schema 2. Readers accept both, now:

- `runs.js`: `runState` maps `cancelled` and `canceled` to the state
  `cancelled` (the plugin's state name, the `runGlyphs.js` key, is unchanged);
  `glyphStateOf` maps both to `cancelled`. `controls`, `RunBadge`, rollups
  follow from those. `normalizeRun` keeps am's spelling in `status`.
- `runs-snapshot.py`: `TERMINAL` holds both.
- `runs-watch.py`: a hello with schema 1 or 2 is accepted and forwarded once as
  `{"hello": {"schema": N, "am": "<version>"}}` (version `""` when missing);
  any other schema stays `SchemaMismatch`. Journal lines are read the same under
  both schemas (the helper reads only `run_id`, `event`, `ts` and a
  `run_upsert`'s `payload.repo_dir`).
- `RunStore`: `amSchema` (0 until a hello arrives) and `amVersion` from that
  line; reset to 0 / `""` when the watch stops or the project switches.
- `RunsScreen` footer: `am <version> · schema N · watching` while a hello is
  known (the S1 mockup), else `am · watching` / `am · not watching`.

## Not changed

- The normalized shape's existing keys and their meaning, so queued milestones
  are unaffected; `rows` keeps per-attempt granularity.
- `runTitle` (milestone id, else short id): the "Run history and titles"
  milestone.
- The `am status` fan-out and the 10-terminal cap in `runs-snapshot.py`; the
  backlog filter in `runs-watch.py`.
- `RunStore`'s public API apart from `amSchema` / `amVersion`; screen layouts;
  `runGlyphs.js` state names; `RunBadge`, `RunRollupBar`, `PhaseTimeline`.
- Deterministic-phase logs (`am logs` without an attempt number) and showing
  Integrate resolver attempts in Run detail.

## Work breakdown (milestone "Align the run model with real am")

1. **Real am fixtures and contract tests** (green: they pin am, not plugin code):
   the contract test over the committed fixtures; the QML fixture loader; the
   helpers' fake am serving the fixtures.
2. **Normalize real am status**: `normalizeRun` (with its red-then-green fixture
   tests in the same subtask), then `rollup`, `runProgress`, `runTree`'s open
   attempt, `escalationReason`, `glyphStateOf`.
3. **Attempt output from real am logs**: `logTail`, `runs-logs.py --repo-dir`,
   `RunStore` passing the root, and a real-data flow test of the whole chain.
4. **Both cancel spellings and both watch schemas**: `runs.js`,
   `runs-snapshot.py`, `runs-watch.py`, `RunStore.amSchema`, the footer.
5. **Docs**, written from the implementation.

## Open questions

- `runProgress` leaves Integrate resolvers out while `am runs` counts them
  (`status-done-integrate.json`: plugin 2/2, am 3/3). Kept as the milestone's own
  subtasks; switch to am's `progress` if the maintainer prefers am's number.
- An Integrate-level escalation carries no reason anywhere in `am status`; the
  row shows `escalated`. A reason needs am to record it (am follow-up).
- Integrate resolver attempts are not reachable from Run detail (no tree node);
  `am logs RUN <story id> --phase resolve` would work.
- `runs-watch.py` still replays every journal before dropping the backlog;
  `--from-now` would remove that cost when the watch is rewritten.
