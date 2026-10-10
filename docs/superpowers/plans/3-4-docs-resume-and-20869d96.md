# 3.4 Docs: resume and recover (card 20869d96)

Parent: story 215a0691. Milestone spec: `docs/superpowers/specs/2026-10-05-resume-recover-design.md` (below: RR). Blocked by 3.3 (b7ef64db, Run detail: Why it stopped and Relaunch), which is done.

## Scope

Docs only. Edit `docs/architecture.md` and `README.md` so they describe the resume and recovery features **as built**. Change no QML, JS, Python, test or other file.

The code wins where it and RR differ. Before writing a sentence, read the code it is about. Every sentence below was checked against these files at the branch head (`25bd402`):

- `core/domain/runs.js`: `controls` refusals (`:875-876`), `controlError` sentences (`:929-930`), `offersRelaunch` (`:956`), `stopReport` and `_relaunchOf` (`:1130-1180`), `stopComment` (`:1239`)
- `core/backend/runs/runs-logs.py`: `logs_argv` (`:50-53`)
- `core/stores/RunStore.qml`: `lastControlErrorType` (`:130`, set `:1195`, cleared `:1201`), `selectAttempt` (`:775`), `openDefaultAttempt` (`:828`), `logsAfterSnapshot` (`:842`), `resumeWithSettings` (`:1251-1275`), the `// ---- resume dialog` section (`:1381-1462`), the `// ---- relaunch` section (`:1890-1909`)
- `ui/components/StopReasonBlock.qml` (header comment `:7-25`), `ui/components/ResumeVerifyDialog.qml`, `ui/components/VerifyCommandsField.qml`
- `ui/screens/RunDetailScreen.qml` (`:44-46`, `belongsTo` `:176`, `noteOf` `:186-200`, `offersRelaunch` `:209`, `relaunch` `:218`, the block `:273-285`)
- `ui/Panel.qml` (the cancel text `:836`, `resumeVerifyDialog` `:850-863`)

### Known RR-vs-built differences the docs must follow

- RR "Architecture" (`:280-283`) has `StopReasonBlock` emit `resumeRequested()`. The built block has **no Resume button** and no such signal: it emits only `openCardRequested(id)` and `relaunchRequested()`. Resume on Run detail stays `RunControls`' button and the `r` key. Do not describe a Resume action in the block.
- RR "Why it stopped" (`:160-163`) says the block's action is Resume or Relaunch. Built: Relaunch is shown when `RunDetailScreen.offersRelaunch(run, report)` is true (below), and Resume is never in the block.
- RR "Behaviour" (`:155-159`) gives the pane heading `Output · <card> <phase> (newest)` for attempt 0. Built as RR says (`RunDetailScreen.qml:327`); the docs may name it.
- RR "Relaunch" (`:211-213`) says a finished or missing target is refused by `dispatchPlan`. Built: a target card that is not on the board opens nothing and flashes `The card to relaunch is no longer on the board` (`RunDetailScreen.qml:223`). A card that is on the board but finished is refused by `openDispatch` as at any dispatch.

## Inherited constraints

- Layering and the docs' section order are as `docs/architecture.md` already has them (RR "Architecture", `:236`). Extend the existing entries. Never write a second copy of an entry.
- Run state is never derived from brd status: `stopReport` reads only the normalised run (RR `:251`).
- am's note is read only for the open project, because `ExtrasStore` exports one board (RR "Limits", `:329-330`).
- A `task` run's resume never opens the dialog (RR `:195`).
- The dialog's verify set is saved with `set-run-settings` for the run's project without waiting, and a failed save flashes `The verify commands could not be saved` (RR `:190-193`).

## docs/architecture.md: what to change

Keep the existing style: dense single-line paragraphs, backticked identifiers, exact strings in backticks. Use no S-tag for this milestone; RR names none.

1. **RunStore, logs paragraph (`:90`).**
   - `selectAttempt` accepts attempt `0`, which means the phase's newest output, as am chooses it.
   - `openDefaultAttempt()` opens the attempt `Runs.stopReport(run)` names, else `Runs.defaultAttempt(run)`. It records the run's `Runs.runState` (`logsRunState`).
   - After a snapshot in which the selected run's state differs from `logsRunState`, the pane reopens on that opening attempt, over any attempt the user picked since.
2. **RunStore, run controls paragraph (`:91`).**
   - Replace "else refuses with a sentence". With no usable stored set and no stored opt-out, the request is settled, nothing is sent to am, and `resumeOpenFor(runId)` opens the Resume dialog. Only an unreadable settings reply still ends in a sentence: `The run settings gave no usable result (exit N).`
   - Add `lastControlErrorType` beside `lastControlError` and `lastControlErrorRunId`: am's error type of the last failed request, `""` when there is none. It is cleared with them.
   - Add the resume dialog section:
     - The state is `resumeRunId` (`""` = closed), `resumeVerify`, `resumeAllowNoVerification` and `resumeError`.
     - `resumeOpenFor(runId)` returns false and changes nothing for an id that is not a non-empty string, a run not in the snapshot, or a `task` run. Otherwise it opens with empty fields, replacing any open dialog.
     - `resumeClose()` closes the dialog.
     - `resumeConfirm()` checks the form first. With no non-blank command and no opt-out, it sets `resumeError` to the verify message of `Runs.validateDispatch`. It then checks `refusalOf("resume", id)`; a refusal sets `resumeError`. In both cases the dialog stays open.
     - Otherwise `resumeConfirm()` starts the request as `control` does. It runs `run-control.py` with the non-blank commands as `--verify` pairs in order, else `--allow-no-verification`. It saves `{verify, allowNoVerification}` with `viewer-state.py set-run-settings <run's project root>` on `resumeSaveRunner` (latest wins, no guard) without waiting for the reply. Then it closes the dialog and returns true.
     - A failed save flashes `The verify commands could not be saved`.
     - The set is saved to the same run settings that later resumes and dispatches read.
3. **RunStore, dispatch paragraph (end of `:92` or the line after it).** Add the relaunch section:
   - `relaunchOpenFor(card, cardMap, relaunch)` returns false and changes nothing when `card` or `relaunch` is not an object, or when `openDispatch` refuses.
   - Otherwise it opens the dispatch as `openDispatch` does. Each of `relaunch.prefix` and `relaunch.base` that is a non-blank string is set, trimmed, over the default.
   - A base set this way is kept over the default-branch lookup (`dispatchBook.baseTouched`).
4. **Shared components list (after `ResumeVerifyDialog`, `:155`).** Add `StopReasonBlock`, as its header comment (`StopReasonBlock.qml:7-25`) states.
   - From top to bottom it shows:
     - `Why it stopped`
     - the headline: the state glyph, `Runs.stopReport`'s headline, the card as `#<first 8>` with its story's title, and a dead run's phase. It is `urgent` for escalated and dead runs.
     - the detail
     - a dead run's `Last heartbeat <age> ago`
     - am's note: a heading with its local time, then one indented `<key>  <value>` line per field
     - the parked cards
     - the Open card and Relaunch buttons
     - the written-out reasons of the shown disabled buttons
   - Presentation only. The owner passes `report`, `note`, `heartbeatAge`, `openCardId`, `openCardReason`, `relaunchOffered` and `relaunchReason`.
   - It emits `openCardRequested(id)` and `relaunchRequested()`, for enabled buttons only.
   - It is visible exactly when `report` is an object.
   - List its objectNames as the header does.
5. **Run screens paragraph (`:167`, the `RunDetailScreen` sentence and the Panel resume sentence).**
   - `RunDetailScreen` mounts the block as `runDetailStop`, between the header's meta line and `RunControls`, with `report` = `Runs.stopReport(run)`.
   - **am's note:**
     - The note is read only when the run belongs to the open project (its `project.root` equals the open root without trailing `/`) and `app.extras` exists.
     - It is `Runs.stopComment` of the report card's comments, else of `run.milestone_id`'s comments.
     - So am's note is shown for the open project's runs only. A run of another project shows no note.
   - **Open card and Relaunch outside the open project:** both are disabled, with `Open this run's project to open its card` and `Open this run's project to relaunch it`.
   - **Open card:** it opens `report.cardId`, else the card the note was found on, through `navigator.openCard`.
   - `heartbeatAge` is `Runs.snapshotAgeText` of `report.heartbeatAt`.
   - **When Relaunch is offered:** the report has a `relaunch` target, and either `Runs.controls(run).resume` is disabled, or the store's last control error is for this run and `Runs.offersRelaunch({type: lastControlErrorType})` is true.
   - **What Relaunch does:**
     - It looks the target card up on the board.
     - If the card is gone, it flashes `The card to relaunch is no longer on the board` and opens nothing.
     - Otherwise it calls `app.runs.relaunchOpenFor(card, app.board.cardMap, report.relaunch)`, so the dispatch dialog opens prefilled with the run's prefix and base.
   - Extend the existing `resumeVerifyDialog` sentence only by what is missing. Panel binds it to `resumeRunId`, `resumeVerify`, `resumeAllowNoVerification` and `resumeError`, writes edits straight to the store, maps confirm to `resumeConfirm()` and maps cancel to `resumeClose()`. Do not repeat the focus/Escape text already there.
6. **Domain helpers, `runs.js` (`:182`).** Add a "Stopped runs" group after "Logs".
   - `stopReport(run)` is null unless `runState` is escalated, parked, dead or cancelled. Otherwise it is `{state, headline, cardId, storyId, storyTitle, phase, detail, heartbeatAt, attempt, parked, relaunch}`:
     - escalated names its escalated subtask, else a synthetic node
     - dead names its in-flight phase and the lease's `heartbeat_at`, at that phase's newest attempt (`0` when the phase records none)
     - parked and cancelled name no card
     - `parked` is the card ids of the subtasks recorded `stopped`
     - `relaunch` is `{level, cardId, prefix, base}`: the run's card for workflow `task`, its story for `story`, else its milestone. Its prefix and base are `branch_prefix` and `base_branch`. It is null when that id is not a real card id.
     - Give the headlines verbatim: `Escalated at <phase>`, `The run's process died`, `Paused at a phase boundary`, `Cancelled. A cancelled run cannot be resumed, only relaunched; cards keep their status`.
   - `stopComment(comments, runId)` takes the newest comment by author `am` whose last line is `am-key: <runId>/…`. It returns `{createdAt, kind, fields}`, with the `reason`, `detail`, `next` and `why` fields in that order, backticks removed and empty values left out. It returns null otherwise.
   - `offersRelaunch(error)` is true only for `NotResumableError` and `CheckpointMismatchError`.
   - The refusal sentences, verbatim:
     - `controls` resume reasons: `A cancelled run cannot be resumed`, `An escalated card run cannot be resumed; relaunch it`
     - `controlError` for `NotResumableError`: `am cannot resume this run (cancelled, finished, or an escalated card run). Relaunch starts a new run of the same work.`
     - `controlError` for `CheckpointMismatchError`: `The workflow changed since this run saved its progress, so it cannot be resumed. Relaunch starts those cards again from their first phase.`
   - Add `card_id` and `story_id` to `normalizeRun`'s scalar list. They prefer the `am runs` row, then the `am status` run (`runs.js:138-139`).
7. **Backend paragraph (`:198`).** Correct the `runs-logs.py` sentence. It sends `--attempt N`, except that `ATTEMPT` `0` sends no `--attempt`, so am returns the phase's newest output; this is how a step whose phases record no attempts gets its output read.

Out of the architecture changes: the Navigator/Shortcuts text (`:96-98`). Its `r` already resumes "on Run detail", which still holds.

## README.md: what to change

Keep the single dense **Runs** bullet (`:154`). Add no heading.

Append to its Run detail text, after "...keeps the last text.":

- **The Why it stopped block.** It shows for escalated, parked, dead and cancelled runs: a headline, the detail, a dead run's last heartbeat, am's own note from the card's comments, the parked cards, **Open card** and **Relaunch**.
- am's note is shown only for runs of the open project. For another project, Open card and Relaunch are disabled until that project is opened.
- The output pane opens on the attempt that failed, or on a step's newest output.
- **Resume** of a milestone run with no saved verify commands opens a Resume dialog. Its commands, or **run without any verification**, are saved for the project and reused by later resumes and dispatches.
- A cancelled run and an escalated card run cannot be resumed. **Relaunch** opens the dispatch dialog prefilled with the run's branch prefix and base. Nothing starts until **Start**.
- Relaunch is also offered after am refuses a resume as not resumable or as checkpoint-mismatched.

Leave lines `:155` (Dispatch), `:235` (am commands) and the Install requirements alone. They make no claim about `am logs --attempt` that this work changes. Check them, and change one only if it does.

## Error paths the docs must state

- No stored verify set on a milestone resume: the Resume dialog opens. Nothing is sent to am.
- Unreadable run settings reply: `The run settings gave no usable result (exit N).`
- Dialog confirm with an empty form, or a run that changed underneath it: the dialog stays open with `resumeError`.
- Verify-set save fails: the resume still runs, and `The verify commands could not be saved` flashes.
- Relaunch target not on the board: `The card to relaunch is no longer on the board`, and nothing opens.
- A run of another project: no note, and Open card and Relaunch are disabled with their reasons.
- am refuses with `NotResumableError` or `CheckpointMismatchError`: the sentence, and Relaunch is offered.

## Tests

No behaviour changes, so there are no new behaviour tests and no new files under `tests/`. No test reads the docs. The card's "tests first" has nothing to assert beyond the gate.

- **Gate (existing, unchanged).** `bash tests/run.sh` is fully green.
  - That covers pytest, including `tests/architecture/test_layers.py` (layering, no duplicated components) and `tests/architecture/test_icon_glyphs.py` (glyph rules, scoped to `ui/` and `vendor/`, so glyphs in `.md` files are outside it).
  - It also covers every QML test. Tier: the suite gate, because the deliverable must leave the whole repo green.
- **Doc-drift guard.** Not in scope. If one is ever added, its only valid tier is `tests/architecture/`.
- **Manual review checks** (not automated; the plan's review step does them):
  - Every identifier, path, objectName and quoted string the new text names exists in the code at those lines.
  - No sentence gives `StopReasonBlock` a Resume button or a `resumeRequested` signal.
  - No sentence claims am's note for a project that is not open.
  - The stale "else refuses with a sentence" (`:91`) and the unconditional `--attempt N` (`:198`) are gone.
  - The archive, dispatch and run-monitor text not named above is unchanged (`git diff` shows only additions or the two corrections).

## Out of scope

- Any code, test or fixture change. Sibling cards 3.1-3.3 built the features, and the 3.x story owns any fix to them.
- RR's "Open" questions: showing the stored set before a resume, and a one-click relaunch for another project.
- `am reset`, and editing what resume reuses (RR Non-goals).
- Any rewording of existing doc text beyond the two stale claims named above.

## Plan handoff

One task is enough: the two doc edits plus the gate run. A reviewer could not approve one file's edit while rejecting the other on separate grounds. The commit message style is `docs: ...`, modelled on `004c9f1`.

---

# 3.4 Docs: resume and recover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `docs/architecture.md` and `README.md` describe the built resume-and-recover features (Resume dialog, Why it stopped block, Relaunch, attempt-0 logs) and drop the two stale claims.

**Architecture:** Docs only. Each change is an exact string replacement that extends an existing paragraph or list entry in place; one new line is added to the shared-components list for `StopReasonBlock`. A throwaway grep check (run from the shell, never saved into the repo) is the RED/GREEN signal; `bash tests/run.sh` is the gate.

**Tech Stack:** Markdown; bash/grep for the check; the repo's existing test gate (`tests/run.sh`: pytest + QML tests).

**Spec:** `docs/superpowers/specs/3-4-docs-resume-and-20869d96.md` (prepended above). Milestone spec: `docs/superpowers/specs/2026-10-05-resume-recover-design.md`.

## Global Constraints

- Change only `docs/architecture.md` and `README.md`. No QML, JS, Python, test, fixture or other file.
- The code wins where it and the milestone spec differ. Every string below was checked against the code at `25bd402`.
- `StopReasonBlock` has no Resume button and no `resumeRequested` signal; never write that it does.
- am's note is shown only for the open project's runs.
- No S-tag for this milestone.
- Keep the docs' style: dense single-line paragraphs, backticked identifiers, exact strings in backticks. README keeps its single **Runs** bullet; add no heading.
- The only rewordings of existing text: "else refuses with a sentence" (architecture `:91`) and the unconditional `--attempt N` (architecture `:198`). Everything else is an insertion (adding `card_id`/`story_id` to the scalar list and `lastControlErrorType` beside its siblings counts as insertion).
- Commit message style: `docs: ...`, like `004c9f1`.
- README names the dispatch button as the code does: **Start run** (`DispatchDialog.qml:463` reads `"Start run"`; the spec's "**Start**" is shorthand).

## Review Focus

1. A reader of the shared-components entry who expects a Resume button in the block: the text must name only Open card and Relaunch, and only `openCardRequested(id)` / `relaunchRequested()` (checked by the Step 1 grep: no `resumeRequested`).
2. A run of another project: docs must say no note is shown and both buttons are disabled with their exact reasons (checked by Step 1's grep for both reason strings).
3. The stale sentences surviving next to the new ones (two contradictory claims): Step 1 asserts `else refuses with a sentence` and `--phase P --attempt N --repo-dir R` are gone.
4. Archive / dispatch / run-monitor text accidentally altered: Step 6 inspects `git diff --word-diff` and expects only insertions apart from the two corrections.
5. A quoted sentence drifting from the code by a character (e.g. a missing final period on a `controlError` sentence): Step 1's grep uses the code's exact strings, so a drifted copy fails the check.

---

### Task 1: Document resume and recover in architecture.md and README.md

**Files:**
- Modify: `docs/architecture.md` (lines 90, 91, 92, after 155, 167, 182, 198)
- Modify: `README.md:154` (the **Runs** bullet)
- Test: no file; the shell check in Step 1, then `bash tests/run.sh`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: nothing code-facing.

- [ ] **Step 1: Write the failing doc check**

Save this to `/tmp/check-3-4-docs.sh` (outside the repo; do not add it to git):

```bash
#!/usr/bin/env bash
# Throwaway doc check for card 20869d96. Run from the worktree root.
set -u
A=docs/architecture.md
R=README.md
fail=0
has() { grep -qF -- "$2" "$1" || { echo "MISSING in $1: $2"; fail=1; }; }
lacks() { if grep -qF -- "$2" "$1"; then echo "STALE in $1: $2"; fail=1; fi; }

# stale claims gone
lacks $A 'else refuses with a sentence'
lacks $A '--phase P --attempt N --repo-dir R'
lacks $A 'resumeRequested'

# RunStore logs
has $A '`selectAttempt` also takes attempt `0`'
has $A 'records the run'"'"'s `Runs.runState` in `logsRunState`'
has $A '`logsAfterSnapshot()`'
# RunStore controls + resume dialog
has $A '`resumeOpenFor(runId)` opens the Resume dialog'
has $A '`The run settings gave no usable result (exit N).`'
has $A '`lastControlErrorType`'
has $A '`resumeRunId` (`""` = closed)'
has $A '`resumeConfirm()` checks the form first'
has $A '`resumeSaveRunner` (latest wins, no guard)'
has $A '`The verify commands could not be saved`'
# relaunch
has $A '`relaunchOpenFor(card, cardMap, relaunch)`'
has $A '`dispatchBook.baseTouched`'
# StopReasonBlock entry
has $A '`StopReasonBlock` (Run detail'"'"'s Why it stopped block'
has $A '`openCardRequested(id)` and `relaunchRequested()`'
has $A '`stopNoteField<i>`'
# RunDetailScreen
has $A '`runDetailStop`'
has $A '`Open this run'"'"'s project to open its card`'
has $A '`Open this run'"'"'s project to relaunch it`'
has $A '`The card to relaunch is no longer on the board`'
has $A '`app.runs.relaunchOpenFor(card, app.board.cardMap, report.relaunch)`'
has $A '`Output · <card> <phase> (newest)`'
has $A 'writes edits straight to the store and maps cancel to `resumeClose()`'
# runs.js
has $A 'Stopped runs: `stopReport(run)`'
has $A '`Cancelled. A cancelled run cannot be resumed, only relaunched; cards keep their status`'
has $A '`am cannot resume this run (cancelled, finished, or an escalated card run). Relaunch starts a new run of the same work.`'
has $A '`The workflow changed since this run saved its progress, so it cannot be resumed. Relaunch starts those cards again from their first phase.`'
has $A '`An escalated card run cannot be resumed; relaunch it`'
has $A '`workflow`, `card_id` and `story_id` prefer the `am runs` row'
# backend
has $A '`ATTEMPT` `0` sends no `--attempt`'
# README
has $R '**Why it stopped**'
has $R 'disabled until that project is opened'
has $R 'opens on the attempt that failed, or on a step'"'"'s newest output'
has $R 'opens a Resume dialog'
has $R 'prefilled with the run'"'"'s branch prefix and base'
has $R 'checkpoint-mismatched'

[ $fail -eq 0 ] && echo "DOC CHECK PASS" || { echo "DOC CHECK FAIL"; exit 1; }
```

- [ ] **Step 2: Run the check to verify it fails**

Run: `bash /tmp/check-3-4-docs.sh`
Expected: `DOC CHECK FAIL`, with `STALE` lines for `else refuses with a sentence` and `--phase P --attempt N --repo-dir R` and many `MISSING` lines.

- [ ] **Step 3: Edit `docs/architecture.md` — RunStore logs, run controls, resume dialog, relaunch**

Apply these exact replacements (each `old` occurs once in the file).

3a. Logs paragraph (`:90`). Replace

```
A failed fetch sets `logsError` and keeps the last good text; another attempt starts from an empty pane.
```

with

```
A failed fetch sets `logsError` and keeps the last good text; another attempt starts from an empty pane. `selectAttempt` also takes attempt `0`, which means the phase's newest output, as am chooses it. `openDefaultAttempt()` opens the attempt `Runs.stopReport(run)` names, else `Runs.defaultAttempt(run)`, and records the run's `Runs.runState` in `logsRunState`; after a snapshot in which the selected run's state differs from `logsRunState` (`logsAfterSnapshot()`), the pane reopens on that opening attempt, over any attempt the user picked since.
```

3b. Run controls paragraph (`:91`), the stale claim. Replace

```
else `--allow-no-verification` when that was chosen, else refuses with a sentence.
```

with

```
else `--allow-no-verification` when that was chosen; with neither, the request is settled, nothing is sent to am, and `resumeOpenFor(runId)` opens the Resume dialog (below). Only a settings reply that cannot be read still ends in a sentence: `The run settings gave no usable result (exit N).`
```

3c. Same paragraph, the control error. Replace

```
sets `lastControlError` (the `Runs.controlError` sentence) and `lastControlErrorRunId`, which no snapshot touches
```

with

```
sets `lastControlError` (the `Runs.controlError` sentence), `lastControlErrorRunId` and `lastControlErrorType` (am's error type of that failure, `""` when there is none), which no snapshot touches
```

3d. Same paragraph, the resume dialog, inserted before the alerts. Replace

```
a project switch keeps the dialog and the flash. Alerts (S2 4.4):
```

with

```
a project switch keeps the dialog and the flash. The Resume dialog is the store's too: `resumeRunId` (`""` = closed), `resumeVerify` (the commands as typed, blanks allowed), `resumeAllowNoVerification` and `resumeError`. `resumeOpenFor(runId)` returns false and changes nothing for an id that is not a non-empty string, a run not in the snapshot or a `task` run (a `task` run's resume never opens the dialog); otherwise it opens with empty fields, replacing any open dialog. `resumeClose()` closes it. `resumeConfirm()` checks the form first: with no non-blank command and no opt-out it sets `resumeError` to the verify message of `Runs.validateDispatch`; it then checks `refusalOf("resume", id)`, and a refusal sets `resumeError`; in both cases the dialog stays open. Otherwise it starts the request as `control` does, running `run-control.py` with the non-blank commands as `--verify` pairs in order, else `--allow-no-verification`; saves `{verify, allowNoVerification}` with `viewer-state.py set-run-settings <run's project root>` on `resumeSaveRunner` (latest wins, no guard) without waiting for the reply -- the same run settings later resumes and dispatches read --; then closes the dialog and returns true. A failed save flashes `The verify commands could not be saved`; the resume still runs. Alerts (S2 4.4):
```

3e. Dispatch paragraph (`:92`), relaunch at its end. Replace

```
`closeDispatch()`, a project switch (even from `starting`) and closing the panel (except while `starting`) put the dispatch back to `idle`.
```

with

```
`closeDispatch()`, a project switch (even from `starting`) and closing the panel (except while `starting`) put the dispatch back to `idle`. Relaunch: `relaunchOpenFor(card, cardMap, relaunch)` (`relaunch` is `Runs.stopReport`'s target) returns false and changes nothing when `card` or `relaunch` is not an object, or when `openDispatch` refuses; otherwise it opens the dispatch as `openDispatch` does, and each of `relaunch.prefix` and `relaunch.base` that is a non-blank string is set, trimmed, over the default -- a base set this way is kept over the default-branch lookup (`dispatchBook.baseTouched`).
```

- [ ] **Step 4: Edit `docs/architecture.md` — StopReasonBlock, run screens, runs.js, backend**

4a. Shared components list, a new entry after `ResumeVerifyDialog` (`:155`). Replace

```
Panel mounts it as `resumeVerifyDialog`),
```

with (two lines: the old line's end, then the new entry on the next line)

```
Panel mounts it as `resumeVerifyDialog`),
`StopReasonBlock` (Run detail's Why it stopped block, top to bottom: `Why it stopped`; the headline -- the state glyph, `Runs.stopReport`'s headline, the card as `#<first 8>` with its story's title, and a dead run's phase -- in `urgent` for escalated and dead runs; the detail; a dead run's `Last heartbeat <age> ago`; am's note, a heading with its local time, then one indented `<key>  <value>` line per field; the parked cards; the Open card and Relaunch buttons; and the written-out reasons of the shown disabled buttons, since a disabled shell Button gets no hover. Presentation only: the owner passes `report`, `note`, `heartbeatAge`, `openCardId`, `openCardReason`, `relaunchOffered` and `relaunchReason`, and it emits `openCardRequested(id)` and `relaunchRequested()`, for enabled buttons only. Visible exactly when `report` is an object. objectNames: `stopReasonBlock`, `stopTitle`, `stopHeadline`, `stopDetail`, `stopHeartbeat`, `stopNoteHeading`, `stopNoteField<i>`, `stopParked`, `stopActions`, `stopOpenCard`, `stopRelaunch`, `stopActionReason`),
```

4b. Run screens paragraph (`:167`), RunDetailScreen. Replace

```
with a Refresh button and `logsError` in `urgent`.
```

with

```
with a Refresh button and `logsError` in `urgent`; an attempt-`0` selection heads the pane `Output · <card> <phase> (newest)`. Between the header's meta line and `RunControls`, `RunDetailScreen` mounts a `StopReasonBlock` as `runDetailStop`, with `report` `Runs.stopReport(run)` and `heartbeatAge` `Runs.snapshotAgeText` of `report.heartbeatAt`. am's note is read only when the run belongs to the open project (its `project.root` equals the open root without trailing `/`) and `app.extras` exists: it is `Runs.stopComment` of the report card's comments, else of `run.milestone_id`'s comments, so am's note is shown for the open project's runs only and a run of another project shows no note. Outside the open project Open card and Relaunch are both disabled, with `Open this run's project to open its card` and `Open this run's project to relaunch it`. Open card opens `report.cardId`, else the card the note was found on, through `navigator.openCard`. Relaunch is offered when the report has a `relaunch` target and either `Runs.controls(run).resume` is disabled, or the store's last control error is for this run and `Runs.offersRelaunch({type: lastControlErrorType})` is true. It looks the target card up on the board: a card that is gone flashes `The card to relaunch is no longer on the board` and opens nothing; otherwise it calls `app.runs.relaunchOpenFor(card, app.board.cardMap, report.relaunch)`, so the dispatch dialog opens prefilled with the run's prefix and base.
```

4c. Same paragraph, the Panel resume sentence. Replace

```
and only its confirm (`resumeConfirm()`) resumes.
```

with

```
and only its confirm (`resumeConfirm()`) resumes. Panel binds it to `resumeRunId`, `resumeVerify`, `resumeAllowNoVerification` and `resumeError`, writes edits straight to the store and maps cancel to `resumeClose()`.
```

4d. Domain helpers, `runs.js` (`:182`), the scalar list. Replace

```
`branch_prefix` and `workflow` prefer the `am runs` row
```

with

```
`branch_prefix`, `workflow`, `card_id` and `story_id` prefer the `am runs` row
```

4e. Same entry, the "Stopped runs" group after "Logs". Replace

```
Logs: `logTail`, `defaultAttempt`, `attemptStatus`.
```

with

```
Logs: `logTail`, `defaultAttempt`, `attemptStatus`. Stopped runs: `stopReport(run)` is null unless `runState` is escalated, parked, dead or cancelled, else `{state, headline, cardId, storyId, storyTitle, phase, detail, heartbeatAt, attempt, parked, relaunch}` -- escalated names its escalated subtask, else a synthetic node; dead names its in-flight phase and the lease's `heartbeat_at`, at that phase's newest attempt (`0` when the phase records none); parked and cancelled name no card; `parked` is the card ids of the subtasks recorded `stopped`; `relaunch` is `{level, cardId, prefix, base}`, the run's card for workflow `task`, its story for `story`, else its milestone, with `branch_prefix` and `base_branch` as prefix and base, and null when that id is not a real card id. Its headlines are `Escalated at <phase>`, `The run's process died`, `Paused at a phase boundary` and `Cancelled. A cancelled run cannot be resumed, only relaunched; cards keep their status`. `stopComment(comments, runId)` takes the newest comment by author `am` whose last line is `am-key: <runId>/…` and returns `{createdAt, kind, fields}`, with the `reason`, `detail`, `next` and `why` fields in that order, backticks removed and empty values left out; null otherwise. `offersRelaunch(error)` is true only for `NotResumableError` and `CheckpointMismatchError`. The refusals: `controls`' resume reasons `A cancelled run cannot be resumed` and `An escalated card run cannot be resumed; relaunch it`; `controlError` for `NotResumableError`, `am cannot resume this run (cancelled, finished, or an escalated card run). Relaunch starts a new run of the same work.`, and for `CheckpointMismatchError`, `The workflow changed since this run saved its progress, so it cannot be resumed. Relaunch starts those cards again from their first phase.`
```

4f. Backend paragraph (`:198`), the stale `--attempt`. Replace

```
is a one-shot `am logs RUN CARD --phase P --attempt N --repo-dir R` passthrough: a 60 s timeout, exactly one JSON line.
```

with

```
is a one-shot `am logs RUN CARD --phase P [--attempt N] --repo-dir R` passthrough: it sends `--attempt N`, except that `ATTEMPT` `0` sends no `--attempt`, so am returns the phase's newest output -- this is how a step whose phases record no attempts gets its output read; a 60 s timeout, exactly one JSON line.
```

Leave the Navigator/Shortcuts text (`:94-98`) alone: its `r` "on Run detail" still holds.

- [ ] **Step 5: Edit `README.md` — the Runs bullet (`:154`)**

Replace

```
It is never a live tail: **Refresh** fetches it again, and a failed fetch says why and keeps the last text.
```

with

```
It is never a live tail: **Refresh** fetches it again, and a failed fetch says why and keeps the last text. For an escalated, parked, dead or cancelled run, a **Why it stopped** block shows a headline, the detail, a dead run's last heartbeat, `am`'s own note from the card's comments, the parked cards, **Open card** and **Relaunch**. `am`'s note is shown only for runs of the open project; for another project, **Open card** and **Relaunch** are disabled until that project is opened. The output pane opens on the attempt that failed, or on a step's newest output. **Resume** of a milestone run with no saved verify commands opens a Resume dialog; its commands, or **run without any verification**, are saved for the project and reused by later resumes and dispatches. A cancelled run and an escalated card run cannot be resumed: **Relaunch** opens the dispatch dialog prefilled with the run's branch prefix and base, and nothing starts until **Start run**. Relaunch is also offered after `am` refuses a resume as not resumable or as checkpoint-mismatched.
```

Check, do not change: README `:155` (Dispatch), `:235` (am commands: `am logs` with no `--attempt` claim) and the Install requirements. Run `grep -n -- '--attempt' README.md` — expected: no output, so nothing there needs changing.

- [ ] **Step 6: Run the check and review the diff**

Run: `bash /tmp/check-3-4-docs.sh`
Expected: `DOC CHECK PASS`

Run: `git diff --word-diff=plain --stat -- docs/architecture.md README.md && git diff --name-only`
Expected: only `README.md` and `docs/architecture.md` changed (plus the untracked spec/plan, which are not yours to touch).

Run: `git diff --word-diff=plain -- docs/architecture.md README.md | grep -o '\[-[^]]*-\]'`
Expected: removals only at the five rewordings -- 3b (`chosen, else refuses with a sentence.`), 3c (`sentence)` / `and` around `lastControlErrorRunId`), 4b (the final `.` after `` `urgent` `` becomes `;`), 4d (`and` / `` `workflow` `` in the scalar list) and 4f (`--attempt N` / `passthrough:`) -- and nothing else. Any other removal means existing text was altered: restore it.

Manual review (spec "Manual review checks"): open each new sentence beside its source — `core/domain/runs.js:875-876, 929-930, 956, 969-972, 1130-1180, 1239`; `core/backend/runs/runs-logs.py:50-53`; `core/stores/RunStore.qml:118, 130, 775, 828, 842, 1195, 1201, 1251-1275, 1381-1462, 1890-1909`; `ui/components/StopReasonBlock.qml:7-46`; `ui/screens/RunDetailScreen.qml:44-46, 176-226, 273-285, 327`; `ui/Panel.qml:850-863` — and confirm every identifier and quoted string matches. Confirm no sentence gives `StopReasonBlock` a Resume button and none claims am's note for a project that is not open.

- [ ] **Step 7: Run the full gate**

Run: `timeout 900 bash tests/run.sh`
Expected: exit 0; pytest all passed (including `tests/architecture/test_layers.py` and `tests/architecture/test_icon_glyphs.py`) and every QML test file with no `FAIL` line.

- [ ] **Step 8: Commit**

```bash
git add docs/architecture.md README.md
git commit -m "docs: resume and recover in architecture and README

Resume dialog, Why it stopped block, Relaunch and attempt-0 logs as built;
drop the stale resume refusal and the unconditional --attempt."
```

Then delete the throwaway check: `rm /tmp/check-3-4-docs.sh`.

---

## Self-review against the spec

- Spec architecture items 1–7: 3a (1), 3b+3c+3d (2), 3e (3), 4a (4), 4b+4c (5), 4d+4e (6), 4f (7). README items: Step 5 (all six bullets). Error paths: no-stored-set (3b, Step 5), unreadable settings (3b), empty form / changed run (3d), save fails (3d), target not on board (4b), another project (4b, Step 5), NotResumable/CheckpointMismatch (4e, 4b, Step 5).
- Inherited constraints: no second copy of an entry (all edits extend in place; `StopReasonBlock` had no entry); run state not from brd (`stopReport` described as reading the run only); note only for open project (4b); `task` run never opens the dialog (3d); save without waiting + flash (3d).
- Code-vs-spec: README uses **Start run** (the button's real label); the block's objectNames include its root `stopReasonBlock` (`StopReasonBlock.qml:28`) besides the header's list.
- Tests: no new test files; Step 7 is the gate.
<!-- task-pipeline: validated -->
