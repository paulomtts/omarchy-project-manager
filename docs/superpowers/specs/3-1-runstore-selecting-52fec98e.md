# 3.1 RunStore: selecting a step — spec

Card `52fec98e-98c0-4c44-8baf-e9ddf0bde034`, subtask of story `053768a8-6bfd-4141-8c91-918e98ea4cf5`
(Live run output). Parent design: `docs/superpowers/specs/2026-10-05-live-output-design.md`
(below: **LO**). Builds on 2.2 (`runs.js`: step entries in `runTree`, `defaultAttempt` on a
started step, `isLiveSelection`; commits `d97f6e8`, `32be7e7`, `604e54b`).

## Purpose

`RunStore` (the Run detail pane's selection and its `am logs` snapshot) learns to select a
**step**: a deterministic phase such as `verify` or `worktree`, which has no numbered attempt.
Today `selectAttempt` refuses anything but an attempt number above 0, so the step entries 2.2
added to the tree, and the step selection `defaultAttempt` now returns, are silently dropped.

## Starting point

- `core/stores/RunStore.qml:116-122`: `selectedAttempt` (`{card_id, phase, attempt}` or null),
  `logsText`, `logsTruncated`, `logsFetchedMs`, `logsLoading`, `logsError`, `logsStatus`. No
  `logsNote`.
- `selectAttempt(cardId, phase, attempt)` (`RunStore.qml:797-810`) returns unless `attempt` is a
  finite number above 0; a selection other than the current one empties text, truncation, time
  and error; it stores `{card_id, phase, attempt}` and calls `fetchLogs`.
- `fetchLogs` (`RunStore.qml:821-829`) sets `logsStatus = Runs.attemptStatus(...)` and launches
  `runs-logs.py` with `[repo_dir, runId, card, phase, String(attempt)]`.
  `core/backend/runs/runs-logs.py` already omits `--attempt` when ATTEMPT is `"0"`; no backend
  change.
- `clearLogs` (`RunStore.qml:832-841`), `openDefaultAttempt` (`844-847`, passes
  `d.card_id, d.phase, d.attempt` and drops `d.step`), `logsAfterSnapshot` (`853-862`, compares
  `Runs.attemptStatus` with `logsStatus`), `applyLogs` (`1053-1070`).
- `Runs.attemptStatus` (`core/domain/runs.js:864`) returns `""` for attempt `<= 0`, so it cannot
  give a step's status. `runs.js` has the private `_findPhase` / `_findByCardId` / `_subtasksOf`;
  `isLiveSelection` (`runs.js:878`) inlines the step's phase status. There is no exported
  phase-status accessor.
- Fixtures: `tests/fixtures/am/status-started.json`'s open subtask (`openCard`,
  `2280a6ab-…`) has phases `worktree` (deterministic, `done`) then `explore` (agent, attempt 1).
  `tests/fixtures/am/logs-follow-refusal.json` is am's recorded refusal for a step with no log:
  `{"ok":false,"error":{"type":"UnknownAttemptError","message":"phase 'worktree' of card '…' has no
  recorded attempt yet"}}`.
- Only outside reader of `selectedAttempt`: `ui/screens/RunDetailScreen.qml:41` (reads
  `.attempt`); it must keep working (a step selection reads attempt 0) but is not changed here.

## Inherited constraints

| constraint | source |
|---|---|
| A step selection is `{card_id, phase, attempt: 0, step: true}`; attempt 0 means "the step's latest", sent to am as no `--attempt`. | LO lines 105-106 |
| Selecting a step whose log does not exist shows `This step records no output` (the step's `UnknownAttemptError`), never an error in `urgent`. | LO lines 107-109; LO line 221 |
| `Runs.defaultAttempt` prefers the current started phase, step or agent, so opening a run whose subtask is in `verify` opens `verify`. | LO lines 109-110 |
| A step has no attempts in `am status`; `am logs RUN CARD --phase P` without `--attempt` answers a step; a step that writes no log is refused with `UnknownAttemptError`. | LO lines 33-40 |
| `runs-logs.py`: ATTEMPT `0` omits `--attempt` (a step). | LO lines 133-135 |
| The snapshot logs stay in `RunStore`; `RunOutputStore` (a later card) reads `RunStore.selectedAttempt` as its `selection`. | LO lines 157-163 |
| `tst_run_store.qml`: selecting a step. | LO line 248 |
| Stores import only QtQml / Quickshell / Quickshell.Io / `../domain`; no duplicated components; icon glyph rules. | `docs/architecture.md`; `tests/architecture/` |
| Docstrings and comments state the contract only, no narrative; `bash tests/run.sh` green; TDD, tests first. | card description |

## Behaviour

**Terms.** A *step request* is `selectAttempt(cardId, phase, 0, true)`: the fourth argument is
the boolean `true` (exactly; `"true"`, `1` and other truthy values are not) and the attempt is the
number `0` exactly. A *numbered request* is a fourth argument that is not exactly `true` (absent
included) and an attempt that is a finite number above 0. The *step's phase status* is the
`status` of the first phase named `phase` of the subtask whose `card_id` is `cardId` in the run's
tree, `""` when there is none or it is not a string.

### B1. `Runs.phaseStatus(run, cardId, phase)` (new, `core/domain/runs.js`)

Pure, never throws, never mutates. Returns the step's phase status as defined above: the
`status` string of `_findPhase(_findByCardId(_subtasksOf(run), cardId), phase)`; `""` for a
non-object run, a synthetic or empty card id, an empty or non-string phase, an unknown card or
phase, or a non-string status. It does not look at `kind` (any phase's status). Placed next to
`attemptStatus`. `isLiveSelection` is not changed.

### B2. `selectAttempt(cardId, phase, attempt, step)`

- Unchanged refusals: no selected run, an empty or non-string card or phase. Then:
  - a step request is accepted;
  - a numbered request is accepted;
  - everything else returns with no change and no launch. In particular attempt `0` without
    `step === true` is refused (as today), and `step === true` with any attempt other than the
    number `0` (`1`, `-1`, `"0"`, `NaN`) is refused.
- The stored selection is `{card_id, phase, attempt: 0, step: true}` for a step request and
  exactly `{card_id, phase, attempt}` (no `step` key) for a numbered request, so existing readers
  and deep compares of a numbered selection are unchanged.
- *Same selection* means same `card_id`, `phase`, `attempt` and same step-ness (`old.step ===
  true` equals the request's). A step and a numbered attempt of the same phase are different
  selections. A different selection empties `logsText`, `logsTruncated`, `logsFetchedMs`,
  `logsError` and `logsNote` before fetching; the same selection keeps them until the reply.
- Every accepted request calls `fetchLogs` (as today).

### B3. `fetchLogs`

- Launch guards unchanged (no selected run, no selection, run not in the snapshot, no
  `repo_dir`).
- `logsStatus` is `Runs.phaseStatus(run, card_id, phase)` for a step selection and
  `Runs.attemptStatus(...)` (as today) for a numbered one.
- The argv is unchanged in shape: `[repo_dir, runId, card_id, phase, String(attempt)]`; for a
  step the last element is `"0"`.

### B4. `logsNote` (new property) and `applyLogs`

`property string logsNote: ""` declared with the other logs properties: a neutral sentence about
the selection's output that is not an error; `""` when there is none.

`applyLogs(stdout, exitCode)`, after `logsLoading = false` and parsing the envelope:

- **Step with no output**: the current selection has `step === true`, the envelope is
  `ok: false` and `envelope.error.type === "UnknownAttemptError"` → `logsText = ""`,
  `logsTruncated = false`, `logsError = ""`, `logsNote = "This step records no output"`,
  `logsFetchedMs = Date.now()` (a definite reply landed).
- **Good reply** (`ok: true`): as today, and `logsNote = ""`.
- **Any other failure** (another error type for a step; any error type for a numbered attempt,
  `UnknownAttemptError` included; an unparseable reply): as today (`logsError` set, text kept),
  and `logsNote = ""`.
- Never touches `amStatus`, `runs`, `lastError` (as today).

`clearLogs` also sets `logsNote = ""`. The file-header comment and the property comments that
describe `selectedAttempt` name the step form.

### B5. `openDefaultAttempt`

Passes the default's step flag through: `selectAttempt(d.card_id, d.phase, d.attempt, d.step ===
true)`. A run whose first started phase is a step therefore opens that step (and fetches it with
`"0"`), both on selecting the run and on the first snapshot that gives a selected run with no
selection its default.

### B6. `logsAfterSnapshot`

For a step selection the status compared with `logsStatus` is `Runs.phaseStatus(...)`; for a
numbered one `Runs.attemptStatus(...)` (as today). A change fetches once; an unchanged status
fetches nothing.

## Out of scope

- `RunOutputStore.qml`, the follow process, `isLiveSelection` callers (sibling card, LO lines
  157-190).
- Any UI: the step row, `logsNote`'s display, `RunDetailScreen.qml` (later story, LO lines
  192-212). It is not edited; it must still load and pass its tests.
- `runs-logs.py` / `runs-logs-follow.py` and any backend file (the step rule already exists).
- `runTree`, `defaultAttempt`, `isLiveSelection` (2.2, done).

## Tests

All in `tests/core/stores/tst_run_store.qml` (QML store tier: the behaviour is store state and the
argv of a `Process` driven through the test's fake reply, which only this tier exercises), next
to the `---- attempt logs (5.2)` section, except T1 (domain tier). Step runs are built from
`treeEntry` copies, marked `// synthetic:`; the refusal reply is the recorded
`logs-follow-refusal.json`.

| # | test | tier, why |
|---|---|---|
| T1 | `Runs.phaseStatus`: the started capture's `worktree` of `openCard` → `"done"`, `explore` → `"started"`; unknown card, unknown phase, synthetic card id, `""`/non-string phase, `null`/`{}` run, a phase with a non-string status → `""`. | `tests/core/domain/tst_runs.qml`: pure function, domain tier |
| T2 | Select a step: `selectAttempt(openCard, "worktree", 0, true)` → `selectedAttempt` deep-equals `{card_id: openCard, phase: "worktree", attempt: 0, step: true}`; `logsLoading` true; `logsStatus` is `"done"`. | store: selection state |
| T3 | Its argv: `tc.logsCmd + "r1|" + openCard + "|worktree|0"`, seven elements. | store: launch argv |
| T4 | The no-output note: reply `logs-follow-refusal.json` → `logsText ""`, `logsTruncated false`, `logsError ""`, `logsNote "This step records no output"`, `logsLoading false`, `logsFetchedMs` within the reply window, `amStatus "ok"`, `lastError ""`. A following good reply (`logsReply`) clears `logsNote` and sets the text. | store: reply mapping |
| T5 | The same `UnknownAttemptError` envelope for a numbered attempt → `logsError "UnknownAttemptError: …"`, `logsNote ""`, text kept. Another error type (`HelperError`) for a step → `logsError` set, `logsNote ""`. | store: the note is step- and type-specific |
| T6 | A status change of the step's phase refetches: a run whose `openCard` `worktree` phase is `started` (synthetic) with the step selected; a snapshot with it still `started` fetches nothing (`logsRunner.seq` unchanged); a snapshot with it `done` fetches once with argv ending `|worktree|0` and `logsStatus "done"`; another identical snapshot fetches nothing. | store: logsAfterSnapshot for a step |
| T7 | A numbered attempt still refuses 0 without step: `selectAttempt(doneCard, "spec", 0)`, `(…, 0, false)`, `(…, 0, "true")`, `(…, 0, 1)`, and `selectAttempt(doneCard, "spec", 1, true)`, `(…, "0", true)` leave the selection and the launcher untouched. A numbered selection made with `step` absent or `false` deep-equals `{card_id, phase, attempt}` (no `step` key). | store: refusals and shape |
| T8 | Step and attempt are distinct selections: with `explore` attempt 1 selected and its text shown, selecting `(openCard, "worktree", 0, true)` empties the text before the reply; re-selecting the same step keeps the text/note until the reply. | store: same-selection rule |
| T9 | Default opens a step: a synthetic run whose `openCard` `worktree` phase is `started`; `selectedRunId = "r1"` → `selectedAttempt` has `step: true`, phase `worktree`, argv ends `|worktree|0`. | store: openDefaultAttempt passes step |
| T10 | `clearLogs` (selecting run `""`) after a no-output reply resets `logsNote` to `""`; `test_logs_defaults` also checks `logsNote` is `""`. | store: reset paths |

Existing tests (notably `test_no_logs_launch_without_a_run_or_a_selection`, the numbered
`selectedAttempt` compares and the run-detail screen tests) must pass unchanged.

## Review focus (for the planner)

1. A truthy but non-boolean `step` (`"true"`, `1`) must not make attempt 0 a step (T7).
2. A late `UnknownAttemptError` for a step selection after the user switched to a numbered
   attempt: the runner's latest-wins drops it; the note is decided by the selection current at
   reply time (T8 covers the switch; no extra code).
3. A step selection whose phase disappears from a later snapshot: `phaseStatus` gives `""`, which
   differs from the stored status, so one refetch happens, then none (covered by B6's rule).
4. `RunDetailScreen.qml` reading `selection.attempt` of a step gets `0` and must not throw (its
   existing tests cover load; no change).
