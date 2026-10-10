# 4.3 Docs: live run output -- design

Card `a120d8bd` (story `1e0d855b`). Parent design:
`docs/superpowers/specs/2026-10-05-live-output-design.md` (cited below as "parent" with its line
numbers). Blocked by `17de0cff` (4.2 RunDetailScreen: the live output pane), which is merged into
this branch.

## Problem

Stories 1-4.2 of this milestone built live run output: `core/backend/runs/runs-logs-follow.py`,
`core/domain/logStream.js`, step entries and `isLiveSelection` in `core/domain/runs.js`, step
selection in `RunStore`, `core/stores/RunOutputStore.qml` wired in `App.qml`, the shared
`ui/components/TailScroll.qml`, and the live pane in `ui/screens/RunDetailScreen.qml`.

`docs/architecture.md` already describes some of it (the `RunOutputStore` bullet at L94,
`TailScroll` at L136, `runs-logs-follow.py` and the step rule of `runs-logs.py` at L203). But
several sentences are now false and several facts are missing:

- L90 (`RunStore` logs) says logs are fetched "never as a live tail", lists `selectedAttempt` as
  `{ card_id, phase, attempt }` only, and has no `logsNote`.
- L172 (`RunDetailScreen`) says Output is "one attempt's `logsText` ... never a live tail, with a
  Refresh button".
- L178 (Refresh model) never mentions the follow process or `RunOutputStore`'s `retryTimer`.
- L187 (`runs.js`) lists "Logs: `logTail`, `defaultAttempt`, `attemptStatus`" -- no step entries
  in `runTree`, no `phaseStatus`, no `isLiveSelection`; and no domain paragraph describes
  `logStream.js`.

`README.md` never mentions live output: L154 says the output pane "is never a live tail", L235
lists the run-monitor helpers without `runs-logs-follow.py` or `am logs --follow`, and L259
(requirements) says nothing about `--follow`.

## Goal

After this card, every sentence about Run detail's output in `docs/architecture.md` and
`README.md` states what the code at the branch head does, including the three facts the card
names:

1. Output arrives in bursts: agent harnesses and `verify` write at the end of a step or command,
   so the pane says `live · waiting for output` until text arrives (parent L41-46).
2. A step's stderr is only in the snapshot: `am logs --follow` streams stdout only; when a
   followed step ends, the pane shows the step's snapshot (parent L87-88, L182-184).
3. An `am` without `--follow` falls back to the snapshot with a sentence saying so, and Refresh
   works (parent L185-187, L218).

The card's rule (card description): state only what the code does. Where code and parent differ,
the docs follow the code.

## Scope

Files changed: `docs/architecture.md` and `README.md` only. No code, test or fixture change.

Out of scope:

- Any code, test, or fixture change, including in the files read below. If the plan author finds
  a code defect while reading, it is reported, not fixed.
- Sibling cards' work: the helper (1.x), `logStream.js` (2.1), `RunOutputStore` (3.x),
  `TailScroll` (4.1), the pane (4.2). This card only describes them.
- Paragraphs of either document unrelated to Run detail's output (dispatch, controls, toasts,
  events, the snapshot/watch model), except where one of their sentences is now false about the
  output pane.
- The parent's open question about "follow the run" mode (parent L254-256): not built, not
  documented.
- Rewriting what is already correct: the L94 `RunOutputStore` bullet, the L136 `TailScroll`
  entry and the L203 `runs-logs-follow.py` / `runs-logs.py` text are verified against the code
  (see "Code facts") and stay, unless a fact there is wrong.

## Code facts (read; quote these, not the parent)

Line numbers below are approximate (they drift with edits); locate each fact by its name.

Each fact below was read from the code at branch head. The docs must not claim more.

### `core/domain/runs.js`

- `runTree`'s subtask node (`_subtaskNode`, from L748): for a step phase (kind exactly
  `deterministic`) that has started or finished, one step entry `{phase, attempt: 0, step: true,
  status}` comes first, then the phase's attempt objects.
- `defaultAttempt(run)` (from L837): the first started phase in subtask and phase order that is a
  step (`{card_id, phase, attempt: 0, step: true}`) or an agent phase with a numbered attempt
  (its newest number); else, walking the flat rows from the last, the newest attempt of a real
  card's row phase; else null.
- `phaseStatus(run, cardId, phase)` (from L876): the card's first phase of that name's status,
  `""` when none.
- `isLiveSelection(run, sel)` (from L886): true only when `runState(run)` is `running` and the
  selection names a real card and a phase, and for `step: true` the card's first phase of that
  name is `started`, else the attempt `{card_id, phase, attempt}` is `started`. Always a boolean.
- `logTail(data, maxLines)` (from L652): the last 200 lines of stdout, then the last 200 lines of
  stderr, as one string (bad `maxLines` = 200).

### `core/domain/logStream.js` (pure, never throws, no function mutates its arguments)

- `sanitize(text)`, `utf8Length(text)`, `emptyBuffer(maxLines)` (`maxLines` kept when a finite
  integer >= 1, else 1000), `foldLine(buffer, line)` -> `{buffer, kind}` with kind `refusal`,
  `hello`, `end`, `chunk` or `ignored`, `bufferText(buffer)`.
- Buffer: `{lines, partial, dropped, nextOffset, gapBytes, slack, maxLines}`.
- A display line is cut to 2000 characters plus `…`; an unterminated tail longer than 16384
  characters is flushed as a line; lines past `maxLines` are dropped from the front and counted
  in `dropped`; a chunk below `nextOffset - slack` is ignored (a duplicate after a resume), one
  past `nextOffset` adds a `[… N bytes not shown]` line and counts `gapBytes`; a hello sets
  `nextOffset` on an empty buffer only; `bufferText` prefixes `… N earlier lines` when
  `dropped > 0`. Exact `sanitize` rules: see the file's own docstring; the doc may summarise
  them as "removes terminal escape sequences and control characters except tab and newline,
  turns `\r\n` into `\n` and keeps only a lone `\r`'s last frame" only if the plan author checks
  that wording against `sanitize` (L84) and `_lastFrame` (L74).

### `core/stores/RunStore.qml`

- `selectedAttempt` (L116): `{ card_id, phase, attempt }`, a step `{ card_id, phase, attempt: 0,
  step: true }`, or null.
- `selectAttempt(cardId, phase, attempt, step)` (L794-821): a step is `step` exactly true with
  attempt exactly 0; an attempt is a number above 0; anything else does nothing. A different
  selection (a step and an attempt of one phase differ) empties the pane first.
- `fetchLogs()` sends `String(sel.attempt)`, so a step goes to `runs-logs.py` as attempt `0`
  (L840-848).
- `logsAfterSnapshot()` (L866-877): the selection is re-fetched when its status -- a step's phase
  status, an attempt's own (`selectionStatus`) -- moved since the fetch was launched.
- `logsNote` (L123, L1066-1096): a step's `UnknownAttemptError` reply empties the text, sets no
  error and sets `logsNote` `This step records no output`; every other reply leaves it `""`.

### `core/stores/RunOutputStore.qml` and `App.qml`

- `App.qml` L139-146: `readonly property RunOutputStore runOutput` with `backendDir`, `active:
  app.panelOpen`, `inRunDetail: app.nav.viewMode === "run"`, `run:
  app.runs.runById(app.runs.selectedRunId)`, `selection: app.runs.selectedAttempt`,
  `onSnapshotWanted: app.runs.refreshLogs()`. This matches architecture L94; L94 stays.
- The store's header comment (L7-45) matches L94 sentence by sentence.

### `ui/screens/RunDetailScreen.qml`

- Reads `app.runOutput` as `ro` (null-guarded; `followStatus` reads `idle` without it or for an
  unknown value) and never imports `core/stores` (L50-59).
- Live mode: `followStatus` is `connecting`, `following`, `ended` or `error` (L59). Otherwise
  (`idle`, `unsupported`, or no `app.runOutput`) it shows the snapshot.
- Status label (`statusLabel`, L177-197):
  - `connecting`, or `following` with `hasOutput` not true: `⟳ live · waiting for output`;
  - `following`: `⟳ live`;
  - `error`: no label; `followError` shows in the `urgent` error line (L384-396);
  - `ended` with an `endStatus`: `ended · <status>`, prefixed with `‼ ` and drawn in `urgent` for
    `gate_failed`, `schema_invalid` and `harness_error` (L173-175, L199-202); `ended` with
    `endStatus` `""`: `followError` (e.g. `This step records no output`);
  - snapshot: `snapshot <age> ago` (plus ` · last 200 lines` when cut), `loading…` before the
    first reply (L153-165); `unsupported` puts `followError` before it, joined by ` · `.
- Glyphs come from `RunGlyphs.glyphOf("running")` / `glyphOf("escalated")` (the
  `runGlyphs.js` rule).
- Live rows (`liveRows`, L204-218) go into a `TailScroll` (`runOutputTail`, L421-440): the
  source text's lines, then `— ended: <status> —` once ended with a status. The source is
  `ro.liveText`, except an ended **step** with a landed snapshot (`logsFetchedMs > 0`), whose
  source is `app.runs.logsText` -- the snapshot that the step's end asked for.
- Refresh (`runOutputRefresh`) is visible only with a selection and outside live mode (L366-370).
- `logsNote` shows as a dim, never urgent line outside live mode (L398-406).
- A step row reads its phase with no attempt number (L132-136) and selects the step; the Output
  heading reads `<phase>` for a step, `<phase>.<n>` for an attempt (L350).

### `core/backend/runs/runs-logs-follow.py` and `runs-logs.py`

Architecture L203 matches the helper's docstring (L1-30): argv, the `am logs ... --follow` argv,
passthrough, refusal, `AmMissing` / `FollowUnsupported` / `SchemaMismatch` / `StreamError` /
`HelperError` / `Usage`, SIGTERM/SIGINT/closed stdout stop am (terminate, 2 s, kill), exit 0 but
`Usage`. L203 stays.

## Required changes

Each item names the paragraph, what is false or missing, and the observable content the new
text must carry. Wording is the plan author's, in each document's style (architecture: one long
line per paragraph or bullet, backticked identifiers, ` -- ` dashes; README: user-facing,
bold UI names, no store or function names except where the paragraph already uses them).

### `docs/architecture.md`

A1. **L90, `RunStore` logs.** Replace "never on a timer and never as a live tail" with: never
on a timer; the live tail is `RunOutputStore`'s. State `selectedAttempt`'s step form
`{ card_id, phase, attempt: 0, step: true }`; `selectAttempt(cardId, phase, attempt, step)` with
the step rule (step exactly true, attempt 0) and that a step and an attempt of one phase are
different selections; a step is fetched with attempt `0`; the re-fetch after a snapshot compares
the step's phase status or the attempt's own status; `logsNote` (`This step records no output`
for a step's `UnknownAttemptError`, no error, text emptied).

A2. **L187, `runs.js`.** In the tree description add the step entry `{phase, attempt: 0, step:
true, status}` for a step phase (kind `deterministic`) that has started or finished, listed
before the phase's attempts. Change "Logs: `logTail`, `defaultAttempt`, `attemptStatus`" to
include `phaseStatus` and `isLiveSelection`, with `defaultAttempt`'s preference for the first
started step or agent phase, `isLiveSelection`'s rule (running run, started step phase or started
attempt), and `logTail`'s "last 200 lines of stdout, then of stderr".

A3. **Domain helpers, new entry for `logStream.js`.** In the L180-187 domain-helpers paragraph,
after `runEvents.js` (or before it; plan author's choice, consistent with the paragraph's order),
add `logStream.js`, the live log stream: pure, never throws, never mutates its arguments; the
five functions; the buffer fields; the 1000-line default cap, the 2000-character line cut, the
16384-character partial flush, duplicate and gap offsets, `… N earlier lines`. Facts only from
"Code facts / logStream.js" above.

A4. **L172, `RunDetailScreen`.** Replace "Output is the output pane: one attempt's `logsText`,
labelled `snapshot <age> ago` plus `· last 200 lines` when it was cut, never a live tail, with a
Refresh button and `logsError` in `urgent`." with the live/snapshot description from "Code facts
/ RunDetailScreen": reads `app.runOutput` too (the first sentence "The run screens read
`app.runs`" must also name `app.runOutput` for Run detail); the live condition; each label;
`followError` in `urgent` for `error`; the end line; the TailScroll; an ended step showing its
snapshot; Refresh and `logsError` only for a snapshot; `logsNote` dim; the step row and heading.
State the burst fact (Goal 1) once here: an agent harness and `verify` write when a step or
command ends, so `live · waiting for output` can last until then. The sentence "Every age on
these screens is read against the clock once per snapshot (or logs reply): there is no timer"
stays.

A5. **L178, Refresh model.** Add: `RunOutputStore`'s follow process is started only while the panel is
open on Run detail (`active` and `inRunDetail`) and the selection is live with a usable
`repo_dir`; at most one exists, and a key that stops being live keeps its process until its end
line or its exit; leaving Run detail or closing the panel stops it (SIGTERM),
cancels a pending restart and keeps the key and buffer, and coming back resumes from
`nextOffset`; its `retryTimer` (1 s, 2 s, 4 s) is the only timer it has and runs only while a
restart waits. Change "the store's one watch is the only watch process" so it stays true next to
the follow process (the follow process is not a watch; say so or reword). "Logs are fetched on
demand" stays, about the snapshot.

A6. **Fallbacks and stderr, once, in A4 or A5.** State Goals 2 and 3 as code facts: `am logs
--follow` streams stdout only, so a step's stderr appears only in its snapshot, which the pane
shows once the step ends; with an `am` without `--follow` (`FollowUnsupported`) or an unknown
stream schema (`SchemaMismatch`) the pane shows the snapshot after the sentence and Refresh
works. Do not repeat what L94 already says in full; a pointer ("see `RunOutputStore`") is enough
for the store side.

A7. **Test-suite bullet near L250.** No change needed: it already says the contract tests pin
`--follow` / `--since-offset`. The plan author confirms and leaves it.

### `README.md`

R1. **L154, Runs bullet.** Replace "an output pane holding one attempt's `am logs` snapshot,
labelled `snapshot <age> ago` and `· last 200 lines` when it was cut. It is never a live tail:
**Refresh** fetches it again, and a failed fetch says why and keeps the last text." with a
user-facing description: the tree lists a row for each step (`verify`, `docs_commit`, ...) that
has started, and the pane shows one attempt or step; while it runs, its output streams live
(`⟳ live`, following the bottom, **Jump ↓** when scrolled up), shows `live · waiting for output`
until the first text -- agent harnesses and `verify` write their output when a step or command
ends, so it arrives in bursts -- and ends with an `— ended: <status> —` line, with no Refresh; a
finished attempt or step shows its snapshot (`snapshot <age> ago`, `· last 200 lines` when cut,
last 200 lines of stdout then of stderr) with **Refresh**, and a failed fetch says why and keeps
the last text; a step's stderr is only in that snapshot, which the pane shows when a followed
step ends; a step that writes no log says `This step records no output`; with an `am` whose
`am logs` has no `--follow` the pane says `This am cannot stream output (am logs --follow is
missing)` and shows the snapshot with Refresh. Live output runs only while the panel is open on
Run detail. The Events text after it stays unchanged, and "Nothing polls while the panel is
closed" stays (still true).

R2. **L235, helper list.** Add `am logs --follow` to the `am` commands and
`runs/runs-logs-follow.py` to the helpers; reword so "never with `--follow`" clearly applies
only to the one-shot `am watch RUN`.

R3. **L259, requirements.** Add: live output needs an `am` whose `am logs` supports `--follow`
and `--since-offset` (agent-manager 0.2.0 has them; the contract test pins them); with an
older `am`, Run detail shows the snapshot and says the am cannot stream output. The plan author
checks `tests/contract/test_am_shapes.py` for the exact pinned flags before writing it.

## Error paths the docs must state

| condition | documented behaviour (from code) |
|---|---|
| `am` without `--follow` | `This am cannot stream output (am logs --follow is missing)`, then the snapshot, Refresh shown |
| hello schema not 1 or 2 | `Unknown output stream schema N`, same fallback |
| `am` missing | follow `idle`, key and buffer held; Run detail shows the missing state |
| step with no log | `This step records no output`, neutral, never urgent |
| refusal or stream error after the hello | `error`, `followError` in `urgent`, no Refresh |
| helper exits without an end line | restart from `nextOffset` after 1 s, 2 s, 4 s; the fourth exit in 60 s: `Live output stopped: the helper exited with code N` |
| end status `gate_failed` / `schema_invalid` / `harness_error` | `‼ ended · <status>` in `urgent` |

Architecture L94 already holds the store-side rows; the screen-side rows go in A4, the
user-visible ones in R1/R3.

## Tests

This card changes prose only. No test in the repo reads `docs/architecture.md` or `README.md`
prose, and the card's "TDD: tests first" has no failing test to write for a sentence; adding a
docs-lint test is out of scope (it would be new tooling the card does not ask for).

| check | tier | why |
|---|---|---|
| `tests/architecture/test_layers.py`, `test_icon_glyphs.py` | architecture (pytest, existing) | the card requires them green; a docs-only change cannot break them, and running them proves no code was touched by accident |
| `bash tests/run.sh` | full suite (pytest + QML, existing) | the card's verification command |
| `git diff --stat main...HEAD -- . ':!docs/architecture.md' ':!README.md' ':!docs/superpowers'` is empty for this card's commits | review check, not committed | proves scope: only the two documents changed |
| `grep -n "never a live tail\|never as a live tail" docs/architecture.md README.md` prints nothing | review check, not committed | the false sentences are gone |
| `grep -c "runs-logs-follow.py" README.md` >= 1; `grep -n "logStream.js" docs/architecture.md` hits the domain-helpers paragraph; `grep -n "isLiveSelection" docs/architecture.md` hits the `runs.js` text; `grep -n "waiting for output" docs/architecture.md README.md` hits both; `grep -n "This am cannot stream output" README.md` hits | review check, not committed | each required fact is present |
| every identifier and quoted string the new text names (`selectAttempt`, `logsNote`, `phaseStatus`, `isLiveSelection`, `retryTimer`, `runOutputTail`, `— ended:`, `This step records no output`, ...) is found by `grep -rn` in `core/` or `ui/` | review check, not committed | "state only what the code does": no invented name |

## Constraints inherited

- Docs describe the code, not the parent (card description; same rule as
  `4-4-1-docs-architecture-9a37973d.md` "Goal").
- One follow at a time, panel-wide, no background tails (parent L91).
- No stderr stream; the snapshot is the way to see a step's stderr (parent L87-88).
- Fallback for an `am` without `--follow` is the snapshot plus the sentence (parent L82-83,
  L185-187, L218).
- Glyphs only from `ui/components/runGlyphs.js` (architecture L176; parent L203); the docs
  quote the glyphs `⟳` and `‼` as `runGlyphs.js` defines them.
- `docs/architecture.md` layering and the architecture tests must pass (card description).
- No `git commit` by the spec author; the plan's commit steps are for the executor.
