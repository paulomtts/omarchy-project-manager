# Resume and recover from runs — design

Status: proposed. Builds on the controls spec (`2026-10-03-am-run-controls-design.md`, S2),
the dispatch spec (`2026-10-03-am-run-dispatch-design.md`, S3), story dispatch
(`2026-10-05-dispatch-story-level-design.md`, S7), global runs
(`2026-10-05-runs-all-projects-design.md`, S6) and dispatch from the Runs screen
(`2026-10-05-dispatch-from-runs-design.md`). It lands BEFORE "Split RunStore"
(`2026-10-05-split-runstore-design.md`), so it is written against the single
`core/stores/RunStore.qml` (`app.runs`): the snapshot, watch, selection and events, the
control requests, the control error, the cancel dialog and flash (S2), the run settings, the
alerts, and S3's dispatch state machine (with S7's story target and the project and target
steps of dispatch from the Runs screen) all live in that one store. Every test that needs
`am` data reads the fixtures the "Align the run model with real am" milestone records under
`tests/fixtures/am/` (`status-escalated.json` above all).

**Where the new state goes.** `RunStore.qml` keeps growing until the split, so this milestone
adds its members as delimited sections the split can lift out whole. Each section opens with
one header line in the file's existing style (`// ---- attempt logs (5.2)` at `:288`,
`// ---- cancel confirmation and the footer flash (S2 4.3)` at `:690`, `// ---- alerts (S2
4.4)` at `:750`) and holds only its own members, all with one prefix:

| section (header line) | members | split target |
|---|---|---|
| `// ---- resume dialog` | `resumeRunId`, `resumeVerify`, `resumeAllowNoVerification`, `resumeError`, `resumeOpenFor(runId)`, `resumeClose()`, `resumeConfirm()`, `resumeSaveRunner`, `resumeSaveReplied(…)` | `RunControlStore` |
| `// ---- relaunch` (right after S3's dispatch section) | `relaunchOpenFor(card, cardMap, relaunch)` | `RunDispatchStore` |

Two changes extend existing members in place instead of adding a section:
`lastControlErrorType` joins the control error pair (`lastControlError`,
`lastControlErrorRunId`, `:68-69`; set in `failControl` `:570-574`, cleared in
`dismissControlError` `:576-579`), and the stopped-run attempt choice changes the selection
(`selectAttempt` `:303-316`, `openDefaultAttempt` `:346-349`, `logsAfterSnapshot`
`:355-364`). Line numbers are main at `84a9217`; S3, S6 and the events timeline add to the
file before this starts, so read it first.

## Problem

When a run escalates, the panel says so (toast, `‼` mark, Needs attention) and then
leaves the user with no next step:

- **Resume refuses with a sentence when no verify set is stored.** A milestone resume
  reads `viewer-state.py get-run-settings` and passes the stored set; with none stored
  and no stored opt-out it ends with "Resume needs verify commands: none are stored for
  this project, and running without verification was not chosen."
  (`core/stores/RunStore.qml:625-647`, the sentence at `:644`). The stored set is
  written only by S3's dispatch dialog, so a run started from a terminal that escalates
  can never be resumed from the panel.
- **The failed output is not opened.** `Runs.defaultAttempt` picks the newest attempt of
  the first `started` phase (`core/domain/runs.js:599-626`); an escalated run has no
  started phase, so the pane falls back to the last row's phase, which is not
  necessarily the one that failed. A failed STEP (a deterministic phase such as `verify`)
  records no attempts in `am status` at all (checked on the real run
  `20261004T165007Z-4a51d663` of `~/Code/agent-manager`: every deterministic phase has
  `attempts: []`), yet `am logs RUN CARD --phase verify` returns its output (`verify.1`,
  `verify.2` exist on disk and `am logs` defaults to the highest recorded). The store
  refuses an attempt number of 0 (`RunStore.qml:306`), so that output is unreachable.
- **The why is in three places.** The failed phase's `detail` is in `am status`, the
  agent's own words (`reason:`) are only in the brd comment am posts on the card, and the
  next command (`next:`, `why:`) is only in that comment too. Real example, card
  `5bfe746d-8ac3-41c4-8e3e-abb939e0b45a` of agent-manager:

  ```
  am · escalated · run 20261004T165007Z-4a51d663
  phase: verify
  detail: VerifyError: could not run none (CLAUDE.md: …)
  next: `am resume 20261004T165007Z-4a51d663`
  why: `am logs 20261004T165007Z-4a51d663 5bfe746d-… --phase verify`
  am-key: 20261004T165007Z-4a51d663/5bfe746d-…/escalated:cef56efb…
  ```

  and on the milestone card `am · escalated · run …`, `escalated: [[<subtask>]] at verify`,
  `next: …`, `am-key: <run>/<milestone>/run-end:<token>`.
- **A cancelled run is a dead end.** `Runs.controls` disables Resume on a cancelled run
  ("A cancelled run cannot be resumed", `runs.js:650`) and offers nothing else; am's own
  answer is a relaunch (`am run --milestone …` again).
- **Refusals read as am's internals.** `RunIsLiveError` reads "The run is still live;
  only a dead run can be resumed", `NotResumableError` "The run cannot be resumed"
  (`runs.js:696-705`); neither says what to do.

## What `am` does (verified, `am resume --help`, `am run --help`, agent-manager README)

- `am resume RUN` continues a `stopped`, `escalated` or killed run under the SAME run id
  from its checkpoints. It takes no `--base-branch`, `--branch-prefix` or
  `--max-concurrent`: they are recorded on the run and reused (README "Relaunching
  resumes").
- **The verify suite is not recorded.** A walk continued from a checkpoint keeps the suite
  it started with; on a milestone run `--verify` (or `--allow-no-verification`) is what
  every subtask with no checkpoint, every merged base and Integrate run, so it must be
  passed again. On a `--card` (`task`) run `--verify` has no effect except for a declined
  checkpoint.
- **An escalated subtask of a `task` run is never resumed** (README: "its newest
  checkpoint was left by a phase escalation … An escalated subtask of a `task` run is never
  resumed"; `NotResumableError`, exit 3). A milestone run's escalated subtask continues at
  the phase that failed.
- Refusals, all `{"ok": false, "error": {type, message}}`, exit 3, nothing written:
  `RunIsLiveError` (another process holds a live lease: wait, or pause it),
  `NotResumableError` (cancelled, done, an escalated `task` subtask, no checkpoint, the
  milestone is gone from the board, or a workflow the resume does not continue),
  `CheckpointMismatchError` (the workflow changed since a checkpoint was saved: relaunch,
  which starts such a card from its first phase). `DeadRunError` is a pause or cancel of a
  run whose process died: resume it (or `am reset` it).
- **Relaunch** is the same `am run --milestone M --branch-prefix P --base-branch B
  --verify …` again: a new run that skips every card already `done`, picks a stopped
  subtask up in its existing worktree, and after a cancel ignores the cancelled run's
  checkpoints. A `--card` run's relaunch is `am run --card X`.

## Goal

From Run detail of a run that stopped, the user sees why in one place, sees the output of
the step that failed, and has one working next action: Resume (asking for the verify
commands when none are stored) or Relaunch (the dispatch dialog, prefilled from the run).

## Non-goals

- No `am reset` from the panel. A dead run is resumed; closing one for good is `am cancel`
  (S2).
- No editing of what resume reuses: prefix, base and parallelism are am's record.
- No new start path: Relaunch is S3's dispatch dialog with its preview, cost warning and
  Start; nothing starts without it.
- No comment fetching for runs of a project that is not open (see Limits).

## Behaviour

### Why it stopped (Run detail)

For a run in state `escalated`, `parked`, `dead` or `cancelled`, Run detail shows a
**Why it stopped** block between the header and the controls:

```
┌ Why it stopped ──────────────────────────────────────────────────────┐
│ ‼ Escalated at verify · #5bfe746d · story "Dry run of a board"       │
│ VerifyError: could not run none (CLAUDE.md: there is no separate …)  │
│ am's note · 17:45                                                    │
│   reason  "tests do not cover the empty list"                        │
│   next    am resume 20261004T165007Z-4a51d663                        │
│ Parked: #6c1e09aa, #9f02b7d1                                         │
│                                   [ Open card ]  [ ⟳ Resume ]        │
└──────────────────────────────────────────────────────────────────────┘
```

- **Escalated:** the escalated subtask (short card id, its story's title), the phase that
  failed and its `detail` (else its newest attempt's `detail`). A failure on a synthetic
  node (`integrate`, `base-<story id>`) names that node as Run detail's tree does.
- **Parked:** "Paused at a phase boundary" and the subtasks recorded `stopped`.
- **Dead:** "The run's process died" with the last heartbeat's age, and the subtask and
  phase that were in flight.
- **Cancelled:** "Cancelled. A cancelled run cannot be resumed, only relaunched; cards keep
  their status", and the subtasks it parked.
- **am's note:** the newest brd comment by author `am` on the escalated subtask's card whose
  `am-key:` line starts with this run's id (else on the milestone card, the `run-end`
  one), shown as its `reason`, `detail`, `next` and `why` lines; hidden when there is
  none. It is read from the OPEN project's comments (`ExtrasStore`, `brd export`), which
  refetch through the board's DB watch when am posts. **Open card** opens that card's
  detail (its comment list shows the whole comment); it is offered only when the run
  belongs to the open project.
- **The failed output opens by itself.** Selecting such a run opens the output pane on
  the attempt the block names: the failed phase's newest attempt, or, for a failed step
  that records none, the phase with attempt `0`, which `runs-logs.py` sends without
  `--attempt` so am returns its newest recorded output. The heading then reads
  `Output · <card> verify (newest)`.
- The block's action is **Resume** when `Runs.controls(run).resume` is enabled, else
  **Relaunch** when the run can be relaunched; a resume that am refused with a
  relaunch-type error (below) adds Relaunch beside the refusal sentence.

### Resume asks for the verify commands

- `RunStore.control("resume", id)` (`:501-530`) on a non-`task` run reads the run settings
  of the run's project (S6: `run.project.root`) as today. With a usable stored set or the
  stored opt-out it resumes at once, as today (`resumeWithSettings`, `:625-647`).
- With neither, it no longer fails (the sentence at `:644`): nothing is asked of am, no
  request stays pending, and the **Resume dialog** opens for that run (`resumeRunId`,
  `resumeVerify`, `resumeAllowNoVerification`, `resumeError`).

```
┌ Resume run …4a51d663 ────────────────────────────────────────┐
│ am does not record the verify commands. They run for every   │
│ subtask without a checkpoint, merged bases and Integrate.    │
│ Verify  [ bash tests/run.sh                    ] [+]          │
│ [ ] Resume without any verification                          │
│ Saved for this project and reused by later resumes and       │
│ dispatches.                                                  │
│                                   [ Cancel ]  [ ⟳ Resume ]   │
└──────────────────────────────────────────────────────────────┘
```

- Resume is enabled when the form passes the verify rule of `Runs.validateDispatch`
  (at least one non-blank command, or the opt-out ticked; the store reads only that rule's
  `verify` error). `resumeConfirm()` re-checks `refusalOf("resume", id)`: a run that changed
  under the dialog keeps it open with `resumeError`. Then it starts the resume with
  `--verify` pairs in order (blank lines dropped) or `--allow-no-verification`, exactly as a
  stored set would, and saves `set-run-settings ROOT {"verify": [...], "allowNoVerification":
  bool}` on its own runner (`resumeSaveRunner`). The resume does not wait for the save; a
  failed save flashes `The verify commands could not be saved`.
- A `task` run's resume never opens the dialog: am ignores `--verify` there.
- `r` and the Resume buttons go through the same `control("resume", …)`, so they open the
  dialog too. The dialog takes the focus while open and gives it back on close; Escape
  closes only it.

### Relaunch

- Offered for a `cancelled` run, an `escalated` `task` run (am never resumes it), and any
  stopped run whose last resume am refused with `NotResumableError` or
  `CheckpointMismatchError`.
- It opens S3's dispatch dialog through `RunStore`'s dispatch state machine
  (`relaunchOpenFor`) with the run's target and the run's recorded prefix and base instead of
  the defaults: a milestone run targets its milestone card, a `task` run its card, a story
  run (S7) its story. Verify and parallelism come from the project's run settings as for any
  dispatch. Everything after that is S3's: preview, cost warning, Start, landing on the new
  run.
- Relaunch is a card entry, so it is bound to the open project (S6; dispatch from the Runs
  screen leaves card entries unchanged). For a run of a project that is not open, Relaunch is
  disabled with "Open this run's project to relaunch it" (the run row's **Open project**
  action from S6 does that). A target card that is no longer on the board, or is finished,
  is refused by `dispatchPlan` as at any dispatch.

### Refusals in user terms

`Runs.controlError` gets sentences that say what to do (the raw am message stays one click
away, as today):

| type | sentence | relaunch offered |
|---|---|---|
| `RunIsLiveError` | Another am process is still driving this run. Wait for it to stop, or pause it; resume only takes over a run whose process died. | no |
| `NotResumableError` | am cannot resume this run (cancelled, finished, or an escalated card run). Relaunch starts a new run of the same work. | yes |
| `CheckpointMismatchError` | The workflow changed since this run saved its progress, so it cannot be resumed. Relaunch starts those cards again from their first phase. | yes |
| `DeadRunError` | The run's process has died, so nobody can act on this request. Resume picks the run up. | no |

`Runs.offersRelaunch(error)` says whether an error type offers Relaunch, and
`RunStore` keeps the type of the last failed request (`lastControlErrorType`) beside
its sentence. `Runs.controls(run).resume` is disabled for an `escalated` run whose
`workflow` is `task`, with "An escalated card run cannot be resumed; relaunch it".

## Architecture

Same layering as S1/S2 (`docs/architecture.md`). `core/domain/runs.js` is a hot file: each
domain subtask keeps its diff to its own functions.

- `core/domain/runs.js`:
  - `controls(run)`: the escalated-`task` resume rule above. `controlError(error)`: the new
    sentences. `offersRelaunch(error)`: true for `NotResumableError` and
    `CheckpointMismatchError` (envelope or bare, as `controlError` reads it).
  - `stopReport(run)`: null unless the run is escalated, parked, dead or cancelled; else
    `{state, headline, cardId, storyId, storyTitle, phase, detail, heartbeatAt, attempt,
    parked, relaunch}`. `attempt` is `{card_id, phase, attempt}` (attempt 0: the phase
    records none) or null; `parked` the card ids recorded `stopped`; `relaunch`
    `{level: "milestone"|"card"|"story", cardId, prefix, base}` or null when the run does not
    name its target. Reads only the normalized run (the aligned model), never brd status.
  - `stopComment(comments, runId)`: from one card's comments (the `ExtrasStore` shape,
    oldest first) the newest whose author is `am` and whose last line is
    `am-key: <runId>/…`; `{createdAt, kind, fields: [{key, value}]}` with the `reason`,
    `detail`, `next` and `why` lines in that order (backticks stripped), or null.
- `core/backend/runs/runs-logs.py`: `ATTEMPT` `0` sends no `--attempt` (am's newest of that
  phase). Everything else unchanged.
- `RunStore` (one store until the split; sections as in the table above):
  - selection: `selectAttempt` accepts attempt 0 for a phase (today it refuses
    `attempt <= 0`, `:306`); when a run is selected (and after a snapshot that moves its
    state) a run with a `stopReport` opens its `attempt` instead of `Runs.defaultAttempt`.
  - control: `lastControlErrorType` beside the control error pair; the no-stored-set branch
    of `resumeWithSettings` settles the request and calls `resumeOpenFor(runId)` instead of
    `failControl`.
  - `// ---- resume dialog`: the dialog state, `resumeOpenFor` / `resumeClose` /
    `resumeConfirm`, and the verify-set save on `resumeSaveRunner` (its own runner, not the
    notify switch's `settingsSaveRunner`, `:870`); a failed save uses the existing `flash`
    (`:705`).
  - `// ---- relaunch`: `relaunchOpenFor(card, cardMap, relaunch)` opens S3's dispatch state
    machine for `card` with `relaunch.prefix` and `relaunch.base` over the defaults. It calls
    the merged S3/S7 card-entry open function (read the dispatch section first; its members
    are named `dispatch*`), so, with dispatch from the Runs screen merged, a relaunch is a
    card entry: `dispatchRoot` is the open project and the project and target steps are
    skipped. Refused (false) without that card.
- UI: the verify editor of S3's `DispatchDialog` becomes a shared
  `ui/components/VerifyCommandsField.qml` (rule: shared before the second use) used by
  `DispatchDialog` and the new `ui/components/ResumeVerifyDialog.qml` (on `ModalCard`),
  which `Panel` mounts like the cancel confirmation. `ui/components/StopReasonBlock.qml`
  (presentation only: the owner passes the report, the comment and the actions; it emits
  `openCardRequested(id)`, `resumeRequested()`, `relaunchRequested()`), placed in
  `RunDetailScreen`, which looks the target card up in `app.board.cardMap` for Relaunch.

## Errors and edge cases

| case | behaviour |
|---|---|
| no stored verify set, milestone run | the Resume dialog, never a sentence |
| the dialog's run changes (resumed elsewhere, cancelled) | the dialog stays open with the refusal |
| saving the verify set fails | the resume still runs; flash `The verify commands could not be saved` |
| `am logs` has no output for the step | the pane's existing error line (`logsError`) |
| am has not posted its comment yet (best-effort, may lag) | no note; it appears when the board refetches |
| run of another project | the block shows without am's note; Open card and Relaunch are disabled with the reason |
| relaunch target card missing or finished | the dispatch dialog's refusal (`dispatchPlan`) |
| `cancelled` and `canceled` | both are the cancelled state (the pending am spelling migration) |

## Testing

- `tests/core/domain/tst_runs.qml`: `controls` for an escalated `task` run and an escalated
  milestone run; every `controlError` sentence and `offersRelaunch` (envelope and bare,
  unknown type); `stopReport` for the escalated, parked, dead and cancelled fixtures
  (`tests/fixtures/am/status-escalated.json`, and states derived from `status-started.json`),
  a failed step (attempt 0), a synthetic node, a story run, both cancel spellings, null for
  running and done; `stopComment` against the real comment bodies above (subtask and
  run-end, another run's comment ignored, a non-am author ignored, newest wins).
- `tests/core/backend/runs/test_runs_logs.py`: attempt `0` sends no `--attempt`; other
  numbers unchanged.
- `tests/core/stores/tst_run_store.qml` (the one store test file until the split moves its
  tests by concern), each group in its own block so the split can move it whole:
  - selection: an escalated run opens its failed attempt, a step opens attempt 0, a running
    run still opens `defaultAttempt`.
  - resume dialog: no stored set opens the dialog and leaves nothing pending; confirm with
    commands (argv order, blanks dropped), with the opt-out, invalid form refused, changed
    run keeps the dialog, save failure flashes but resumes, a `task` run never opens it,
    `lastControlErrorType` set and cleared.
  - relaunch: `relaunchOpenFor` overrides prefix and base, keeps verify from settings, uses
    the open project as `dispatchRoot`, refuses a missing card.
- `tests/ui/components/`: `VerifyCommandsField` (add, remove, opt-out), `ResumeVerifyDialog`,
  `StopReasonBlock` (each state, note hidden, actions' enabled and reasons).
- `tests/ui/tst_runs_flow.qml`: escalated run → block and failed output; Resume with no
  stored set → dialog → resume launched; cancelled run → Relaunch → dispatch dialog
  prefilled.

## Limits

- am's note is read only for the open project: `ExtrasStore` exports one board. A run of
  another project shows the block from `am status` alone.
- The output of a failed step is am's newest for that phase; after a resume ran the step
  again that is the newer try.

## Open

- Should Resume of a run WITH a stored set also show the set before starting (the S2 spec's
  "milestone runs show the verify set about to be reused")? This spec keeps today's
  one-click resume and adds the dialog only when nothing is stored. Recommendation: keep it;
  the Why-it-stopped block could later show the stored set as a line.
- Relaunch for a run of a project that is not open: opening the project first and then the
  dialog in one click would need cross-store choreography in `Panel`. Recommendation: keep
  it disabled with the reason until S6's Open project is in use and the need is shown.
