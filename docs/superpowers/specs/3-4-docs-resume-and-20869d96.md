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
