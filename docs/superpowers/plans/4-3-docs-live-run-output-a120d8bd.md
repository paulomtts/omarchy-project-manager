# 4.3 Docs: live run output Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every sentence about Run detail's output in `docs/architecture.md` and `README.md` state what the code at the branch head does -- the live follow, step entries, `logStream.js`, the burst / stderr / no-`--follow` facts -- and nothing more.

**Architecture:** Prose only. Each task replaces named paragraphs with exact text given here (written against the code, which was read for this plan) using exact-string edits. Because no test reads prose, each task's "failing test" is a `grep` that shows the false sentence present or the required fact absent; it must flip after the edit. The existing suite (`bash tests/run.sh`) proves no code was touched.

**Tech Stack:** Markdown; `grep`; pytest + `qmltestrunner` via `bash tests/run.sh`.

**Spec:** `docs/superpowers/specs/4-3-docs-live-run-output-a120d8bd.md` (copied verbatim below, headings demoted one level).

## Global Constraints

- Files changed: `docs/architecture.md` and `README.md` only. No code, test or fixture change.
- Docs describe the code, not the parent design; where they differ, the docs follow the code.
- Architecture style: one long line per paragraph or bullet, backticked identifiers, ` -- ` dashes. README style: user-facing, bold UI names, no store or function names except where the paragraph already uses them.
- Glyphs are quoted as `runGlyphs.js` defines them: running `⟳`, escalated `‼`.
- Paragraphs unrelated to Run detail's output stay unchanged; architecture L94 (`RunOutputStore`), L136 (`TailScroll`), L203 (`runs-logs-follow.py`) and the test-suite bullet near L250 stay unchanged.
- Never use `git commit --amend`, `git stash`, or edit any file under `core/`, `ui/`, `tests/`.

## Review Focus

1. **An identifier or quoted string the new text names that the code does not have** (a reader greps for it and finds nothing). Pinned by Task 4 Step 3, which greps every name and string the new text introduces in `core/` and `ui/`.
2. **The ended-step case** (a step that ends while followed): a reader expects the pane to show the step's snapshot, including stderr, not the streamed stdout. Pinned by Task 2 Step 1's grep for `streams stdout only` and Task 3 Step 1's README grep.
3. **An `am` without `--follow`**: a reader expects the snapshot plus a sentence and a working Refresh, not an error. Pinned by Task 2 Step 1 (`This am cannot stream output` in architecture) and Task 3 Step 1 (README).
4. **`logsText` length**: the old text says "at most 200 lines", but `Runs.logTail` keeps up to 200 of stdout *and* 200 of stderr. Pinned by Task 1 Step 1's grep for `at most 200 lines)` (must vanish).
5. **Scope creep**: an edit landing outside the two documents. Pinned by Task 4 Step 2 (`git diff --stat 94160e2..HEAD` names only the two files plus the spec/plan docs). Note: `main...HEAD` holds the whole milestone, so the check compares against `94160e2`, the 4.2 tip this card starts from.

## Code defect noted while reading (reported, not fixed)

- `core/stores/RunStore.qml:115` comment still says the Run detail pane's snapshot is "Never a live tail." It is true of `RunStore` alone (the live tail is `RunOutputStore`'s) but reads as a claim about the pane. Out of scope for this card (no code change); left for a follow-up.

---

## The spec (verbatim)

## 4.3 Docs: live run output -- design

Card `a120d8bd` (story `1e0d855b`). Parent design:
`docs/superpowers/specs/2026-10-05-live-output-design.md` (cited below as "parent" with its line
numbers). Blocked by `17de0cff` (4.2 RunDetailScreen: the live output pane), which is merged into
this branch.

### Problem

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

### Goal

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

### Scope

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

### Code facts (read; quote these, not the parent)

Line numbers below are approximate (they drift with edits); locate each fact by its name.

Each fact below was read from the code at branch head. The docs must not claim more.

#### `core/domain/runs.js`

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

#### `core/domain/logStream.js` (pure, never throws, no function mutates its arguments)

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

#### `core/stores/RunStore.qml`

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

#### `core/stores/RunOutputStore.qml` and `App.qml`

- `App.qml` L139-146: `readonly property RunOutputStore runOutput` with `backendDir`, `active:
  app.panelOpen`, `inRunDetail: app.nav.viewMode === "run"`, `run:
  app.runs.runById(app.runs.selectedRunId)`, `selection: app.runs.selectedAttempt`,
  `onSnapshotWanted: app.runs.refreshLogs()`. This matches architecture L94; L94 stays.
- The store's header comment (L7-45) matches L94 sentence by sentence.

#### `ui/screens/RunDetailScreen.qml`

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

#### `core/backend/runs/runs-logs-follow.py` and `runs-logs.py`

Architecture L203 matches the helper's docstring (L1-30): argv, the `am logs ... --follow` argv,
passthrough, refusal, `AmMissing` / `FollowUnsupported` / `SchemaMismatch` / `StreamError` /
`HelperError` / `Usage`, SIGTERM/SIGINT/closed stdout stop am (terminate, 2 s, kill), exit 0 but
`Usage`. L203 stays.

### Required changes

Each item names the paragraph, what is false or missing, and the observable content the new
text must carry. Wording is the plan author's, in each document's style (architecture: one long
line per paragraph or bullet, backticked identifiers, ` -- ` dashes; README: user-facing,
bold UI names, no store or function names except where the paragraph already uses them).

#### `docs/architecture.md`

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

#### `README.md`

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

### Error paths the docs must state

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

### Tests

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

### Constraints inherited

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

---

## File Structure

| file | change | owner |
|---|---|---|
| `docs/architecture.md` L90 (`RunStore` logs bullet) | rewrite | Task 1 |
| `docs/architecture.md` L187 (`runs.js` text, new `logStream.js` entry) | edit + insert | Task 1 |
| `docs/architecture.md` L172 (run screens paragraph) | two edits | Task 2 |
| `docs/architecture.md` L178 (Refresh model) | edit | Task 2 |
| `README.md` L154 (Runs bullet) | edit | Task 3 |
| `README.md` L235 (helper list) | edit | Task 3 |
| `README.md` L259 (run-monitor requirements) | append | Task 3 |

How to edit: every edit below is an exact-string replacement (the Edit tool, or any editor). `old` is copied from the file at branch head and is unique in it; replace it with `new` verbatim. The lines are very long; do not re-wrap them.

---

### Task 1: architecture.md -- the snapshot store and the domain helpers

**Files:**
- Modify: `docs/architecture.md:90` (`RunStore` logs bullet)
- Modify: `docs/architecture.md:187` (`runs.js`'s tree and Logs text; new `logStream.js` entry before `runEvents.js`)

**Interfaces:**
- Consumes: nothing.
- Produces: the names Task 2's text points at (`RunOutputStore`, `logsNote`, `logStream.js`) are described here.

- [ ] **Step 1: Write the failing check**

```bash
grep -n "never as a live tail" docs/architecture.md        # expect a hit (L90): must vanish
grep -n "at most 200 lines)" docs/architecture.md          # expect a hit (L90): must vanish
grep -n "logsNote" docs/architecture.md                    # expect no hit: must hit L90
grep -n "isLiveSelection(run, sel)" docs/architecture.md   # expect no hit: must hit the runs.js text
grep -n "\`logStream.js\`, the live log stream" docs/architecture.md   # expect no hit: must hit
grep -n "step: true, status}" docs/architecture.md         # expect no hit: must hit
```

- [ ] **Step 2: Run it to see it fail**

Run the six commands. Expected now: the first two print a line (L90), the last four print nothing.

- [ ] **Step 3: Rewrite the `RunStore` logs bullet (L90)**

old:

```
  Run detail's output pane is a second `HelperRunner`, `logsRunner` (`runs-logs.py` with the selected run's `repo_dir` first, then the run, card, phase and attempt; no guard, so a reply is applied whatever project is open; nothing launches for a selected run with no `repo_dir`): `selectedAttempt` (`{ card_id, phase, attempt }` or null), `logsText` (`Runs.logTail` of the last good reply, at most 200 lines), `logsTruncated`, `logsFetchedMs`, `logsLoading`, `logsError` and `logsStatus` (the attempt's status when its fetch was launched). Logs are fetched on demand only -- `selectAttempt(...)`, `openDefaultAttempt()` when a run is selected, `refreshLogs()` (the Refresh button), and after a snapshot that moved the selected attempt's status -- never on a timer and never as a live tail. A failed fetch sets `logsError` and keeps the last good text; another attempt starts from an empty pane.
```

new:

```
  Run detail's output snapshot is a second `HelperRunner`, `logsRunner` (`runs-logs.py` with the selected run's `repo_dir` first, then the run, card, phase and attempt -- `String(attempt)`, so a step goes as attempt `0`; no guard, so a reply is applied whatever project is open; nothing launches for a selected run with no `repo_dir`): `selectedAttempt` (`{ card_id, phase, attempt }`, a step `{ card_id, phase, attempt: 0, step: true }`, or null), `logsText` (`Runs.logTail` of the last good reply: the last 200 lines of stdout, then the last 200 lines of stderr), `logsTruncated`, `logsFetchedMs`, `logsLoading`, `logsError`, `logsStatus` (the selection's status when its fetch was launched, `selectionStatus`: a step's phase status, an attempt's own) and `logsNote` (a neutral sentence, never an error: a step's `UnknownAttemptError` reply empties the text, sets no `logsError` and sets `logsNote` to `This step records no output`; every other reply leaves it `""`). `selectAttempt(cardId, phase, attempt, step)` takes a step (`step` exactly true, `attempt` exactly 0) or an attempt (`attempt` a number above 0) and does nothing for anything else; a step and an attempt of one phase are different selections, and a different selection starts from an empty pane. Logs are fetched on demand only -- `selectAttempt(...)`, `openDefaultAttempt()` when a run is selected, `refreshLogs()` (the Refresh button, and `RunOutputStore`'s `snapshotWanted()`), and after a snapshot that moved the selection's status (`logsAfterSnapshot`) -- never on a timer; the live tail is `RunOutputStore`'s (below), not `RunStore`'s. A failed fetch sets `logsError` and keeps the last good text.
```

- [ ] **Step 4: Add the step entry to `runTree` (L187)**

old:

```
Card mapping: `runsTouching` and `runTree`, through `run.milestone_id`, `stories[].card_id` and `subtasks[].card_id`, never through rows alone;
```

new:

```
Card mapping: `runsTouching` and `runTree`, through `run.milestone_id`, `stories[].card_id` and `subtasks[].card_id`, never through rows alone; a `runTree` subtask node lists its `attempts` in phase order, a step phase (kind exactly `deterministic`) that has started or finished giving one step entry `{phase, attempt: 0, step: true, status}` before that phase's attempt entries;
```

- [ ] **Step 5: Replace the Logs list (L187)**

old:

```
Logs: `logTail`, `defaultAttempt`, `attemptStatus`. Run state
```

new:

```
Logs: `logTail(data, maxLines)` (`{text, truncated}`: the last `maxLines` lines of stdout, then the last `maxLines` lines of stderr, as one text; a bad `maxLines` is 200), `defaultAttempt(run)` (the first started phase, in subtask and phase order, that is a step -- `{card_id, phase, attempt: 0, step: true}` -- or an agent phase with a numbered attempt -- its newest; else, walking the rows from the last, the newest attempt of a real card's row phase; else null), `attemptStatus`, `phaseStatus(run, cardId, phase)` (the status of the card's first phase of that name, `""` when none) and `isLiveSelection(run, sel)` (true only while `runState(run)` is running and `sel` names a real card and a phase, and for `step: true` the card's first phase of that name is `started`, else the attempt `{card_id, phase, attempt}` is `started`; always a boolean). Run state
```

- [ ] **Step 6: Insert the `logStream.js` entry before `runEvents.js` (L187)**

old:

```
reports closed (merged, canceled, archived); `runEvents.js`, the run events timeline:
```

new:

```
reports closed (merged, canceled, archived); `logStream.js`, the live log stream, folds the JSON lines `runs-logs-follow.py` prints into a bounded buffer: pure JS, never throws, and no function mutates its arguments. `sanitize(text)` removes ANSI CSI, OSC and other ESC sequences, turns `\r\n` into `\n`, reduces each line to its last non-empty `\r` frame and removes C0 controls other than tab and newline, and DEL (`""` for a non-string); `utf8Length(text)` is the UTF-8 byte length (a lone surrogate counts 3); `emptyBuffer(maxLines)` is `{lines, partial, dropped, nextOffset, gapBytes, slack, maxLines}`, `maxLines` kept when a finite integer of 1 or more, else 1000; `foldLine(buffer, line)` returns `{buffer, kind}`, the buffer a new copy, `kind` `refusal` (`ok` false), `hello` (event `logs`; it sets `nextOffset` to its offset on an empty buffer only), `end` (event `end`), `chunk` (`{offset, text}`) or `ignored`. A chunk below `nextOffset - slack` is ignored (a duplicate after a resume); one past `nextOffset` first adds a `[… N bytes not shown]` line and counts the bytes in `gapBytes`; a display line is cut to 2000 characters plus `…`, an unterminated tail longer than 16384 characters is flushed as a line, and lines past `maxLines` are dropped from the front and counted in `dropped`. `bufferText(buffer)` is the display text: `… N earlier lines` when `dropped` > 0, the lines, then the unterminated tail; `runEvents.js`, the run events timeline:
```

- [ ] **Step 7: Run the check to see it pass**

Run the six commands from Step 1. Expected: the first two print nothing; each of the last four prints exactly one line (L90 for `logsNote`; L187 for the other three).

- [ ] **Step 8: Run the architecture tests**

Run: `timeout 300 python3 -m pytest tests/architecture -q` (if `python3` has no pytest: `timeout 300 uv run --with pytest python3 -m pytest tests/architecture -q`)
Expected: all pass.

- [ ] **Step 9: Commit**

```bash
git add docs/architecture.md
git commit -m "docs(architecture): RunStore's step selections and logsNote, runs.js step entries and isLiveSelection, logStream.js"
```

---

### Task 2: architecture.md -- Run detail's live pane and the refresh model

**Files:**
- Modify: `docs/architecture.md:172` (run screens paragraph: first sentence and the Output sentence)
- Modify: `docs/architecture.md:178` (Refresh model)

**Interfaces:**
- Consumes: Task 1's text (the `RunStore` bullet now says the live tail is `RunOutputStore`'s).
- Produces: nothing other tasks read.

- [ ] **Step 1: Write the failing check**

```bash
grep -n "never a live tail" docs/architecture.md              # expect a hit (L172): must vanish
grep -n "read \`app.runs\` and never import" docs/architecture.md   # expect a hit: must vanish
grep -n "waiting for output" docs/architecture.md             # expect no hit: must hit L172
grep -n "streams stdout only" docs/architecture.md            # expect no hit: must hit L172
grep -n "This am cannot stream output" docs/architecture.md   # expect one hit (L94): must be two (L94, L172)
grep -n "runOutputTail" docs/architecture.md                  # expect no hit: must hit L172
grep -n "only timer" docs/architecture.md                     # expect no hit: must hit L178
```

- [ ] **Step 2: Run it to see it fail**

Run the seven commands. Expected now: the first two print a line; `This am cannot stream output` prints one line (L94); the others print nothing.

- [ ] **Step 3: Name `app.runOutput` in the run screens' first sentence (L172)**

old:

```
The run screens read `app.runs` and never import `core/stores`.
```

new:

```
The run screens read `app.runs` (Run detail also `app.runOutput`, null-guarded) and never import `core/stores`.
```

- [ ] **Step 4: Replace the Output sentence (L172)**

old:

```
Output is the output pane: one attempt's `logsText`, labelled `snapshot <age> ago` plus `· last 200 lines` when it was cut, never a live tail, with a Refresh button and `logsError` in `urgent`.
```

new:

```
Output is the output pane, headed `Output · <card> <phase>` for a step and `Output · <card> <phase>.<n>` for an attempt; a step row of the tree reads its phase with no attempt number and selects the step. The pane is in live mode while `app.runOutput`'s `followStatus` is `connecting`, `following`, `ended` or `error` (it reads `idle` without `app.runOutput` or for a value it does not name), and shows the snapshot otherwise (`idle`, `unsupported`). Live, the status label reads `⟳ live · waiting for output` while connecting, or following with no output yet (`hasOutput` not true) -- an agent harness and `verify` write when a step or command ends, so output arrives in bursts and this label can last until then -- then `⟳ live`; once ended, `ended · <status>` (`‼ ended · <status>`, in `urgent`, for `gate_failed`, `schema_invalid` and `harness_error`), or `followError` for an end without a status (`This step records no output`); for `error` it shows no label and `followError` in the `urgent` error line. The live text is a `TailScroll` (`runOutputTail`): the lines of `liveText`, then `— ended: <status> —` once ended with a status. `am logs --follow` streams stdout only, so a step's stderr is only in its snapshot: an ended step whose snapshot has landed (the one its end asked for) shows that snapshot's `logsText` lines instead of `liveText`. Live mode has no Refresh. The snapshot is the selection's `logsText`, labelled `snapshot <age> ago` plus `· last 200 lines` when it was cut (`loading…` before the first reply), with a Refresh button (`runOutputRefresh`, shown only with a selection and outside live mode), `logsError` in `urgent` and `logsNote` as a dim line, never urgent. With `unsupported` -- an `am` without `--follow` (`FollowUnsupported`) or an unknown stream schema (`SchemaMismatch`) -- the label puts `followError` (`This am cannot stream output (am logs --follow is missing)` or `Unknown output stream schema N`) before the snapshot's label, joined by ` · `, and Refresh works; see `RunOutputStore` for when a follow runs and how it fails.
```

- [ ] **Step 5: Add the follow process to the Refresh model (L178)**

old:

```
Logs are fetched on demand; the selected run's events are fetched on a selection, on `refreshEvents()` and on a nudge naming that run, never on a timer, and the store's one watch is the only watch process;
```

new:

```
Logs are fetched on demand; the selected run's events are fetched on a selection, on `refreshEvents()` and on a nudge naming that run, never on a timer, and `RunStore`'s one watch is the only watch process. Live output is `RunOutputStore`'s follow process, which is not a watch: at most one exists, and it is started only while the panel is open on Run detail (`active` and `inRunDetail`) and the selection is live (`Runs.isLiveSelection`) with a non-empty `repo_dir`; a key that stops being live keeps its process until its end line or its exit; leaving Run detail or closing the panel stops it (SIGTERM), cancels a pending restart and keeps the key and the buffer, and coming back on the same live key resumes from the buffer's `nextOffset`; its `retryTimer` (1 s, 2 s, then 4 s) is its only timer and runs only while a restart waits;
```

- [ ] **Step 6: Run the check to see it pass**

Run the seven commands from Step 1. Expected: the first two print nothing (the run screens sentence now reads `read \`app.runs\` (Run detail also`); `This am cannot stream output` prints two lines (L94, L172); every other command prints one line, at the line named in Step 1.

Also confirm the unchanged sentences survive:

```bash
grep -c "Every age on these screens is read against the clock once per snapshot (or logs reply): there is no timer." docs/architecture.md   # expect 1
grep -c "Logs are fetched on demand;" docs/architecture.md   # expect 1
```

- [ ] **Step 7: Run the architecture tests**

Run: `timeout 300 python3 -m pytest tests/architecture -q`
Expected: all pass.

- [ ] **Step 8: Commit**

```bash
git add docs/architecture.md
git commit -m "docs(architecture): Run detail's live output pane, its fallbacks, and the follow process in the refresh model"
```

---

### Task 3: README.md -- live output for the user

**Files:**
- Modify: `README.md:154` (Runs bullet: the output pane sentences)
- Modify: `README.md:235` (helper list)
- Modify: `README.md:259` (run-monitor requirements)

**Interfaces:**
- Consumes: nothing.
- Produces: nothing.

- [ ] **Step 1: Write the failing check**

```bash
grep -n "never a live tail" README.md                  # expect a hit (L154): must vanish
grep -n "waiting for output" README.md                 # expect no hit: must hit L154
grep -n "This am cannot stream output" README.md       # expect no hit: must hit L154 and L259
grep -n "streams stdout only" README.md                # expect no hit: must hit L154
grep -n "This step records no output" README.md        # expect no hit: must hit L154
grep -c "runs-logs-follow.py" README.md                # expect 0: must be 1
grep -n "\-\-since-offset" README.md                   # expect no hit: must hit L259
```

- [ ] **Step 2: Run it to see it fail**

Run the seven commands. Expected now: the first prints L154, the `grep -c` prints `0`, the others print nothing.

- [ ] **Step 3: Replace the output pane sentences (L154)**

old:

```
and an output pane holding one attempt's `am logs` snapshot, labelled `snapshot <age> ago` and `· last 200 lines` when it was cut. It is never a live tail: **Refresh** fetches it again, and a failed fetch says why and keeps the last text.
```

new:

```
and an output pane. The tree also lists a row for each step `am` runs itself (`verify`, `docs_commit`, ...) once it has started, and the pane shows one attempt or one step. While that attempt or step is running, its output streams live (`⟳ live`) and follows the bottom, with **Jump ↓** when scrolled up; it reads `⟳ live · waiting for output` until the first text arrives -- agent harnesses and `verify` write their output when a step or command ends, so it arrives in bursts -- and ends with an `— ended: <status> —` line (the label reads `‼ ended · <status>` for a failed gate, an invalid schema or a harness error). Live output has no **Refresh**, and it runs only while the panel is open on Run detail. A finished attempt or step shows its `am logs` snapshot -- the last 200 lines of stdout, then the last 200 lines of stderr -- labelled `snapshot <age> ago` and `· last 200 lines` when it was cut; **Refresh** fetches it again, and a failed fetch says why and keeps the last text. `am logs --follow` streams stdout only, so a step's stderr is only in its snapshot, which the pane shows once a followed step ends. A step that writes no log says `This step records no output`. With an `am` whose `am logs` has no `--follow`, the pane says `This am cannot stream output (am logs --follow is missing)` and shows the snapshot, with **Refresh**.
```

- [ ] **Step 4: Add the follow command and helper (L235)**

old:

```
`am watch --all-projects --follow`, `am logs` and the one-shot `am watch RUN [--since SEQ]`, never with `--follow`) through the helpers in `core/backend/runs/` (`runs/runs-snapshot-all.py`, `runs/runs-watch.py`, `runs/runs-logs.py`, `runs/runs-events.py`)
```

new:

```
`am watch --all-projects --follow`, `am logs`, `am logs --follow` for live output, and the one-shot `am watch RUN [--since SEQ]`, which never takes `--follow`) through the helpers in `core/backend/runs/` (`runs/runs-snapshot-all.py`, `runs/runs-watch.py`, `runs/runs-logs.py`, `runs/runs-logs-follow.py`, `runs/runs-events.py`)
```

- [ ] **Step 5: Add the live-output requirement (L259)**

old:

```
`tests/contract/test_am_shapes.py` fails when the installed `am` lacks `--story`.
```

new:

```
`tests/contract/test_am_shapes.py` fails when the installed `am` lacks `--story`. Live output in Run detail needs an `am` whose `am logs` supports `--follow` and `--since-offset` (agent-manager 0.2.0 has them); with an older `am`, Run detail says `This am cannot stream output (am logs --follow is missing)` and shows the snapshot, whose **Refresh** works. The same contract test fails when `am logs --help` lists neither or only one of them.
```

- [ ] **Step 6: Run the check to see it pass**

Run the seven commands from Step 1. Expected: the first prints nothing; `This am cannot stream output` prints two lines (L154, L259); `grep -c` prints `1`; each other command prints one line at the line named in Step 1.

Also confirm the unchanged sentences survive:

```bash
grep -c "Nothing polls while the panel is closed." README.md   # expect 1
grep -c "Run detail's bottom area has \*\*Output\*\* and \*\*Events\*\* tabs" README.md   # expect 1
```

- [ ] **Step 7: Commit**

```bash
git add README.md
git commit -m "docs(readme): Run detail's live output, its bursts, stderr and the am without --follow"
```

---

### Task 4: Verify scope, names and the suite

**Files:** none changed (review checks only; nothing here is committed).

**Interfaces:**
- Consumes: Tasks 1-3's text.

- [ ] **Step 1: The false sentences are gone**

Run: `grep -n "never a live tail\|never as a live tail" docs/architecture.md README.md`
Expected: no output.

- [ ] **Step 2: Only the two documents changed**

Run: `git diff --stat 94160e2..HEAD -- . ':!docs/architecture.md' ':!README.md' ':!docs/superpowers'`
Expected: no output. (`94160e2` is the 4.2 tip this card starts from; `main...HEAD` would list the whole milestone.)

- [ ] **Step 3: Every name the new text introduces exists in the code**

Run:

```bash
for s in selectAttempt selectionStatus logsAfterSnapshot logsNote phaseStatus isLiveSelection defaultAttempt \
         emptyBuffer foldLine bufferText utf8Length sanitize gapBytes nextOffset retryTimer runOutputTail \
         runOutputRefresh followError hasOutput liveText snapshotWanted inRunDetail \
         "This step records no output" "This am cannot stream output (am logs --follow is missing)" \
         "Unknown output stream schema" "— ended: " "live · waiting for output" "bytes not shown" \
         "earlier lines" "FollowUnsupported" "UnknownAttemptError"; do
  n=$(grep -rnF -- "$s" core ui | wc -l); echo "$n  $s"; done
```

Expected: every count is 1 or more. Any `0` means the docs name something the code does not have: fix the doc text, never the code.

- [ ] **Step 3b: The test-suite bullet still pins the follow options (spec A7, no edit)**

Run: `grep -n "pin \`am logs --help\` listing \`--follow\` and" docs/architecture.md`
Expected: one line (near L251), unchanged by this card.

- [ ] **Step 4: Run the full suite**

Run: `timeout 600 bash tests/run.sh`
Expected: pytest reports all passed (contract tests may skip when `am` is absent), and every QML `Totals` line shows `0 failed`; exit status 0.

- [ ] **Step 5: No commit**

Nothing to commit: this task changes no file. If Step 3 forced a doc fix, commit it:

```bash
git add docs/architecture.md README.md
git commit -m "docs: name only what the code has in the live output text"
```
<!-- task-pipeline: validated -->
