# 3.1 RunStore: selecting a step Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `RunStore` can select a deterministic step (`{card_id, phase, attempt: 0, step: true}`), fetch its `am logs` with attempt `"0"`, say `This step records no output` when am has no log for it, open a started step by default, and refetch it when its phase status moves.

**Architecture:** A new pure `Runs.phaseStatus` gives a phase's own status. `RunStore.selectAttempt` gains a fourth `step` argument; a store helper `selectionStatus` picks `phaseStatus` or `attemptStatus` for `fetchLogs` and `logsAfterSnapshot`; `applyLogs` maps a step's `UnknownAttemptError` to a new `logsNote` property; `openDefaultAttempt` passes the default's step flag.

**Tech Stack:** QML (Qt 6, Quickshell), plain JS domain module, QtTest via `tests/run.sh` (qmltestrunner, offscreen).

**Spec:** `docs/superpowers/specs/3-1-runstore-selecting-52fec98e.md` (reproduced in full below)

---

## Spec

## 3.1 RunStore: selecting a step — spec

Card `52fec98e-98c0-4c44-8baf-e9ddf0bde034`, subtask of story `053768a8-6bfd-4141-8c91-918e98ea4cf5`
(Live run output). Parent design: `docs/superpowers/specs/2026-10-05-live-output-design.md`
(below: **LO**). Builds on 2.2 (`runs.js`: step entries in `runTree`, `defaultAttempt` on a
started step, `isLiveSelection`; commits `d97f6e8`, `32be7e7`, `604e54b`).

### Purpose

`RunStore` (the Run detail pane's selection and its `am logs` snapshot) learns to select a
**step**: a deterministic phase such as `verify` or `worktree`, which has no numbered attempt.
Today `selectAttempt` refuses anything but an attempt number above 0, so the step entries 2.2
added to the tree, and the step selection `defaultAttempt` now returns, are silently dropped.

### Starting point

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

### Inherited constraints

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

### Behaviour

**Terms.** A *step request* is `selectAttempt(cardId, phase, 0, true)`: the fourth argument is
the boolean `true` (exactly; `"true"`, `1` and other truthy values are not) and the attempt is the
number `0` exactly. A *numbered request* is a fourth argument that is not exactly `true` (absent
included) and an attempt that is a finite number above 0. The *step's phase status* is the
`status` of the first phase named `phase` of the subtask whose `card_id` is `cardId` in the run's
tree, `""` when there is none or it is not a string.

#### B1. `Runs.phaseStatus(run, cardId, phase)` (new, `core/domain/runs.js`)

Pure, never throws, never mutates. Returns the step's phase status as defined above: the
`status` string of `_findPhase(_findByCardId(_subtasksOf(run), cardId), phase)`; `""` for a
non-object run, a synthetic or empty card id, an empty or non-string phase, an unknown card or
phase, or a non-string status. It does not look at `kind` (any phase's status). Placed next to
`attemptStatus`. `isLiveSelection` is not changed.

#### B2. `selectAttempt(cardId, phase, attempt, step)`

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

#### B3. `fetchLogs`

- Launch guards unchanged (no selected run, no selection, run not in the snapshot, no
  `repo_dir`).
- `logsStatus` is `Runs.phaseStatus(run, card_id, phase)` for a step selection and
  `Runs.attemptStatus(...)` (as today) for a numbered one.
- The argv is unchanged in shape: `[repo_dir, runId, card_id, phase, String(attempt)]`; for a
  step the last element is `"0"`.

#### B4. `logsNote` (new property) and `applyLogs`

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

#### B5. `openDefaultAttempt`

Passes the default's step flag through: `selectAttempt(d.card_id, d.phase, d.attempt, d.step ===
true)`. A run whose first started phase is a step therefore opens that step (and fetches it with
`"0"`), both on selecting the run and on the first snapshot that gives a selected run with no
selection its default.

#### B6. `logsAfterSnapshot`

For a step selection the status compared with `logsStatus` is `Runs.phaseStatus(...)`; for a
numbered one `Runs.attemptStatus(...)` (as today). A change fetches once; an unchanged status
fetches nothing.

### Out of scope

- `RunOutputStore.qml`, the follow process, `isLiveSelection` callers (sibling card, LO lines
  157-190).
- Any UI: the step row, `logsNote`'s display, `RunDetailScreen.qml` (later story, LO lines
  192-212). It is not edited; it must still load and pass its tests.
- `runs-logs.py` / `runs-logs-follow.py` and any backend file (the step rule already exists).
- `runTree`, `defaultAttempt`, `isLiveSelection` (2.2, done).

### Tests

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

### Review focus (for the planner)

1. A truthy but non-boolean `step` (`"true"`, `1`) must not make attempt 0 a step (T7).
2. A late `UnknownAttemptError` for a step selection after the user switched to a numbered
   attempt: the runner's latest-wins drops it; the note is decided by the selection current at
   reply time (T8 covers the switch; no extra code).
3. A step selection whose phase disappears from a later snapshot: `phaseStatus` gives `""`, which
   differs from the stored status, so one refetch happens, then none (covered by B6's rule).
4. `RunDetailScreen.qml` reading `selection.attempt` of a step gets `0` and must not throw (its
   existing tests cover load; no change).

---

## Global Constraints

- A step selection is `{card_id, phase, attempt: 0, step: true}`; attempt 0 means "the step's latest", sent to am as no `--attempt` (runs-logs.py already does this for ATTEMPT `"0"`; no backend change).
- A numbered selection stays exactly `{card_id, phase, attempt}` -- no `step` key.
- Only the boolean `true` as the fourth argument makes a step request, and only with attempt the number `0`.
- The no-output note text is exactly `This step records no output`; it is never put in `logsError` (never shown in `urgent`).
- Stores import only QtQml / Quickshell / Quickshell.Io / `../domain`; no new imports are needed.
- Docstrings and comments state the contract only, no narrative.
- `bash tests/run.sh` green at the end of every task; tests first (RED before GREEN).
- Do not edit `ui/screens/RunDetailScreen.qml`, `RunOutputStore.qml`, any backend file, `runTree`, `defaultAttempt` or `isLiveSelection`.
- Synthetic test data is marked with a `// synthetic:` comment.

## Review Focus

1. A truthy but non-boolean `step` (`"true"`, `1`) with attempt 0 must be refused, not treated as a step -- Task 2 (`test_a_step_needs_step_true_and_attempt_0`).
2. A late `UnknownAttemptError` reply for a step after the user switched to a numbered attempt must change nothing (latest-wins), and the numbered attempt's own `UnknownAttemptError` must show as an error, not the note -- Task 3 (`test_a_late_step_refusal_after_switching_to_an_attempt_is_dropped`).
3. A step selection whose phase disappears from a later snapshot refetches once (status `""`), then never again -- Task 4 (`test_a_step_whose_phase_disappears_refetches_once`).
4. A selected run whose first started phase is a step, opened before any phase exists, picks the step on the snapshot that brings it -- Task 4 (`test_a_run_opened_before_its_first_phase_picks_a_started_step`).
5. Leaving the run (`selectedRunId = ""`) after a no-output reply must not leave the note behind for the next run -- Task 3 (`test_clearing_the_run_clears_the_note`).

---

### Task 1: `Runs.phaseStatus`

**Files:**
- Modify: `core/domain/runs.js:863-872` (add `phaseStatus` right after `attemptStatus`, before the `isLiveSelection` comment)
- Test: `tests/core/domain/tst_runs.qml:2349` (new test right after `test_attempt_status`)

**Interfaces:**
- Consumes: private `_isCardId(id)`, `_findPhase(subtask, name)`, `_findByCardId(list, cardId)`, `_subtasksOf(run)`, `_isObject(v)`, `_stringOr(v)` already in `runs.js`.
- Produces: `Runs.phaseStatus(run, cardId, phase) -> string` -- the `status` of the first phase named `phase` of the subtask `cardId`, `""` otherwise. Tasks 2 and 4 call it.

- [ ] **Step 1: Write the failing test**

Insert after the closing `}` of `test_attempt_status` (line 2349) in `tests/core/domain/tst_runs.qml`:

```qml
  function test_phase_status() {
    var card = "2280a6ab-9c40-434b-9729-63fd1f373754"
    var started = Runs.normalizeRun(amRun("status-started.json"))
    var before = JSON.stringify(started)
    compare(Runs.phaseStatus(started, card, "worktree"), "done", "the capture's worktree step")
    compare(Runs.phaseStatus(started, card, "explore"), "started", "an agent phase's own status")
    compare(Runs.phaseStatus(started, "00000000-0000-0000-0000-000000000000", "worktree"), "", "an unknown card")
    compare(Runs.phaseStatus(started, card, "verify"), "", "an unknown phase")
    var phases = ["", null, undefined, 3, {}, []]
    for (var i = 0; i < phases.length; i++)
      compare(Runs.phaseStatus(started, card, phases[i]), "", "phase " + JSON.stringify(phases[i]))
    var cards = ["", null, undefined, 7, {}]
    for (var c = 0; c < cards.length; c++)
      compare(Runs.phaseStatus(started, cards[c], "worktree"), "", "card " + JSON.stringify(cards[c]))
    var runs = [null, undefined, {}, "x", 5, []]
    for (var r = 0; r < runs.length; r++)
      compare(Runs.phaseStatus(runs[r], card, "worktree"), "", "run " + JSON.stringify(runs[r]))
    compare(JSON.stringify(started), before, "the run is not changed")

    // synthetic: a non-string status, a repeated phase name and bookkeeping ids with started phases
    var odd = { tree: { subtasks: [
      { card_id: "t9", phases: [{ name: "verify", status: 5 }, { name: "verify", status: "done" }] },
      { card_id: "t8", phases: [{ name: "verify", kind: "deterministic", status: "started" }, { name: "verify", status: "done" }] },
      { card_id: "integrate", phases: [{ name: "integrate", status: "started" }] },
      { card_id: "bases", phases: [{ name: "bases", status: "started" }] },
      { card_id: "base-s1", phases: [{ name: "worktree", status: "started" }] }
    ] } }
    compare(Runs.phaseStatus(odd, "t9", "verify"), "", "the first phase of the name has no string status")
    compare(Runs.phaseStatus(odd, "t8", "verify"), "started", "the first phase of that name decides")
    compare(Runs.phaseStatus(odd, "integrate", "integrate"), "", "integrate is not a card")
    compare(Runs.phaseStatus(odd, "bases", "bases"), "", "bases is not a card")
    compare(Runs.phaseStatus(odd, "base-s1", "worktree"), "", "base-* is not a card")
  }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/run.sh core/domain/tst_runs.qml`
Expected: `FAIL!  : DomainRuns::test_phase_status()` with `TypeError: Property 'phaseStatus' of object [object Object] is not a function`.

- [ ] **Step 3: Write minimal implementation**

In `core/domain/runs.js`, directly after the closing `}` of `attemptStatus` (line 872) and before `// Whether a selection is in flight: ...`, insert:

```js

// The status of the card's first phase named `phase`, step or agent; "" when
// there is none or its status is not a string.
function phaseStatus(run, cardId, phase) {
  if (!_isCardId(cardId)) return ""
  var p = _findPhase(_findByCardId(_subtasksOf(run), cardId), phase)
  return _isObject(p) ? _stringOr(p.status) : ""
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/run.sh core/domain/tst_runs.qml`
Expected: `Totals:` line with `0 failed`, no `FAIL` lines.

- [ ] **Step 5: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(domain): phaseStatus gives a phase's own status, step or agent"
```

---

### Task 2: `selectAttempt` accepts a step; `fetchLogs` launches it with `"0"`

**Files:**
- Modify: `core/stores/RunStore.qml:16-17` (header comment), `:116` (`selectedAttempt` comment), `:794-810` (`selectAttempt`), `:817-829` (`fetchLogs`, plus new `selectionStatus` just above it)
- Test: `tests/core/stores/tst_run_store.qml` (new tests after `test_logs_argv_keeps_an_odd_repo_dir_verbatim`, which ends just before `// ---- run controls (S2 4.1)`, around line 2716)

**Interfaces:**
- Consumes: `Runs.phaseStatus(run, cardId, phase) -> string` (Task 1); `Runs.attemptStatus(run, cardId, phase, attempt) -> string` (existing).
- Produces:
  - `store.selectAttempt(cardId, phase, attempt, step)` -- `step` optional; `(cardId, phase, 0, true)` selects `{card_id, phase, attempt: 0, step: true}`.
  - `store.selectionStatus(run, sel) -> string` -- `Runs.phaseStatus` for `sel.step === true`, else `Runs.attemptStatus`. Task 4 uses it in `logsAfterSnapshot`.

- [ ] **Step 1: Write the failing tests**

In `tests/core/stores/tst_run_store.qml`, after the closing `}` of `test_logs_argv_keeps_an_odd_repo_dir_verbatim` and before `// ---- run controls (S2 4.1)`, insert:

```qml
  // ---- selecting a step (3.1)

  // treeEntry with openCard's `worktree` step (phase 0, done in the capture)
  // at `status`; its explore attempt 1 stays started.
  function stepEntry(id, status) {
    var e = treeEntry(id, "started")
    // synthetic: the worktree step's status is the test's; no capture has a started step
    e.status.stories[1].subtasks[1].phases[0].status = status
    return e
  }

  // logs-follow-refusal.json, am's refusal for a step with no log, as one JSON line.
  function refusalReply() {
    return JSON.stringify(F.load("logs-follow-refusal.json")) + "\n"
  }

  function test_selecting_a_step_stores_the_step_form_and_its_phase_status() {
    var store = opened(); if (!store) return
    compare(store.selectedAttempt.phase, "explore", "the capture opens explore 1")
    store.selectAttempt(tc.openCard, "worktree", 0, true)
    compare(JSON.stringify(store.selectedAttempt),
            JSON.stringify({ card_id: tc.openCard, phase: "worktree", attempt: 0, step: true }))
    compare(store.logsLoading, true)
    compare(store.logsStatus, "done", "the worktree phase's own status")
  }

  function test_a_step_launches_with_attempt_0() {
    var store = opened(); if (!store) return
    store.selectAttempt(tc.openCard, "worktree", 0, true)
    var proc = store.logsRunner.current
    compare(argv(proc), tc.logsCmd + "r1|" + tc.openCard + "|worktree|0")
    compare(proc.command.length, 7)
  }

  // Review Focus 1.
  function test_a_step_needs_step_true_and_attempt_0() {
    var store = opened(); if (!store) return
    var seq = store.logsRunner.seq
    var shown = JSON.stringify(store.selectedAttempt)
    store.selectAttempt(tc.doneCard, "spec", 0)
    store.selectAttempt(tc.doneCard, "spec", 0, false)
    store.selectAttempt(tc.doneCard, "spec", 0, "true")
    store.selectAttempt(tc.doneCard, "spec", 0, 1)
    store.selectAttempt(tc.doneCard, "spec", 1, true)
    store.selectAttempt(tc.doneCard, "spec", "0", true)
    store.selectAttempt(tc.doneCard, "spec", -1, true)
    store.selectAttempt(tc.doneCard, "spec", NaN, true)
    store.selectAttempt(tc.doneCard, "", 0, true)
    store.selectAttempt("", "worktree", 0, true)
    compare(store.logsRunner.seq, seq, "nothing launched")
    compare(JSON.stringify(store.selectedAttempt), shown, "the selection is unchanged")
    store.selectAttempt(tc.doneCard, "spec", 1)
    compare(Object.keys(store.selectedAttempt).join(","), "card_id,phase,attempt", "no step key with step absent")
    store.selectAttempt(tc.doneCard, "spec", 1, false)
    compare(Object.keys(store.selectedAttempt).join(","), "card_id,phase,attempt", "no step key with step false")
    compare(JSON.stringify(store.selectedAttempt), JSON.stringify({ card_id: tc.doneCard, phase: "spec", attempt: 1 }))
  }

  function test_a_step_without_a_selected_run_launches_nothing() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([treeEntry("r1", "started")]), 0)
    store.selectAttempt(tc.openCard, "worktree", 0, true)
    verify(!store.logsRunner.current, "no run selected")
    compare(store.selectedAttempt, null)
  }

  function test_a_step_and_an_attempt_are_different_selections() {
    var store = opened(); if (!store) return
    reply(store.logsRunner.current, logsReply("explore text\n"), 0)
    compare(store.logsText, "explore text")
    store.selectAttempt(tc.openCard, "worktree", 0, true)
    compare(store.logsText, "", "the attempt's text is never shown under the step")
    compare(store.logsFetchedMs, 0)
    compare(store.logsTruncated, false)
    compare(store.logsError, "")
    reply(store.logsRunner.current, logsReply("worktree text\n"), 0)
    compare(store.logsText, "worktree text")
    store.selectAttempt(tc.openCard, "worktree", 0, true)
    compare(store.logsText, "worktree text", "the same step keeps its text until the reply")
    verify(store.logsFetchedMs > 0)
    compare(store.logsLoading, true)
    compare(argv(store.logsRunner.current), tc.logsCmd + "r1|" + tc.openCard + "|worktree|0")
  }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run.sh core/stores/tst_run_store.qml`
Expected: FAIL for `test_selecting_a_step_stores_the_step_form_and_its_phase_status` (selection still explore), `test_a_step_launches_with_attempt_0` (argv still `|explore|1`) and `test_a_step_and_an_attempt_are_different_selections` (text `"explore text"` kept). `test_a_step_needs_step_true_and_attempt_0` and `test_a_step_without_a_selected_run_launches_nothing` may already pass (they pin refusals that hold today, and must keep holding).

- [ ] **Step 3: Write minimal implementation**

In `core/stores/RunStore.qml`, header comment lines 16-17, replace:

```qml
// act on each run's own repo_dir and project root. Plus the selected run, the
// attempt the Run detail pane shows and that
// attempt's `am logs` snapshot (runs-logs.py), and whether `am` could be
```

with:

```qml
// act on each run's own repo_dir and project root. Plus the selected run, the
// attempt or step the Run detail pane shows and its `am logs` snapshot
// (runs-logs.py; a step is fetched with attempt "0"), and whether `am` could be
```

Line 114-116, replace:

```qml
  // The Run detail pane (5.2): which attempt of the selected run it shows and
  // that attempt's last `am logs` snapshot. Never a live tail.
  property var selectedAttempt: null  // { card_id, phase, attempt } or null
```

with:

```qml
  // The Run detail pane (5.2): which attempt or step of the selected run it
  // shows and its last `am logs` snapshot. Never a live tail.
  property var selectedAttempt: null  // { card_id, phase, attempt }, a step { card_id, phase, attempt: 0, step: true }, or null
```

Replace the whole `selectAttempt` function and its comment (lines 794-810) with:

```qml
  // Shows (and fetches) one attempt or one step of the selected run. A step is
  // (cardId, phase, 0, true) -- `step` exactly true, attempt exactly 0 -- and
  // is stored as { card_id, phase, attempt: 0, step: true }; an attempt has
  // `step` anything else and a number above 0, and is stored as
  // { card_id, phase, attempt }. Another selection than the one shown (a step
  // and an attempt of one phase differ) starts from an empty pane -- its
  // predecessor's text is never shown under its heading. Nothing happens
  // without a selected run, a non-empty card and phase, and one of those forms.
  function selectAttempt(cardId, phase, attempt, step) {
    if (store.selectedRunId === "") return
    if (typeof cardId !== "string" || cardId === "" || typeof phase !== "string" || phase === "") return
    var isStep = step === true
    if (isStep && attempt !== 0) return
    if (!isStep && (typeof attempt !== "number" || !isFinite(attempt) || attempt <= 0)) return
    var old = store.selectedAttempt
    if (!old || old.card_id !== cardId || old.phase !== phase || old.attempt !== attempt
        || (old.step === true) !== isStep) {
      store.logsText = ""
      store.logsTruncated = false
      store.logsFetchedMs = 0
      store.logsError = ""
    }
    store.selectedAttempt = isStep ? { card_id: cardId, phase: phase, attempt: 0, step: true }
                                   : { card_id: cardId, phase: phase, attempt: attempt }
    store.fetchLogs()
  }
```

Replace the `fetchLogs` comment and function (lines 817-829) with:

```qml
  // The selection's status in `run`: its phase's for a step, its attempt's otherwise.
  function selectionStatus(run, sel) {
    return sel.step === true ? Runs.phaseStatus(run, sel.card_id, sel.phase)
                             : Runs.attemptStatus(run, sel.card_id, sel.phase, sel.attempt)
  }

  // One runs-logs.py launch for the selection, the selected run's repo_dir
  // first, remembering the status it was launched for (a snapshot that changes
  // it fetches again). Nothing launches for a run not in the snapshot or one
  // with no repo_dir.
  function fetchLogs() {
    var sel = store.selectedAttempt
    if (store.selectedRunId === "" || !sel) return
    var run = store.runById(store.selectedRunId)
    if (run === null || typeof run.repo_dir !== "string" || run.repo_dir === "") return
    store.logsStatus = store.selectionStatus(run, sel)
    store.logsLoading = true
    logsRunner.run([run.repo_dir, store.selectedRunId, sel.card_id, sel.phase, String(sel.attempt)])
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run.sh core/stores/tst_run_store.qml`
Expected: `0 failed`; every pre-existing logs test (notably `test_no_logs_launch_without_a_run_or_a_selection`) still passes.

- [ ] **Step 5: Run the whole suite**

Run: `bash tests/run.sh`
Expected: exit 0, no `FAIL` lines (the run-detail screen and flow tests still compare numbered selections with no `step` key).

- [ ] **Step 6: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(stores): selectAttempt selects a step and fetches it with attempt 0"
```

---

### Task 3: `logsNote` -- a step with no output

**Files:**
- Modify: `core/stores/RunStore.qml` -- the logs property block (after `property string logsStatus`, line ~123), `selectAttempt` (the emptying block from Task 2), `clearLogs` (~line 838), `applyLogs` and its comment (~lines 1057-1074)
- Test: `tests/core/stores/tst_run_store.qml` -- `test_logs_defaults` (~line 2434) and new tests appended to the `// ---- selecting a step (3.1)` section from Task 2

**Interfaces:**
- Consumes: `store.selectAttempt(cardId, phase, attempt, step)` and the `stepEntry`/`refusalReply` test helpers (Task 2).
- Produces: `property string logsNote` -- `"This step records no output"` after a step's `UnknownAttemptError` reply, `""` otherwise. A later UI card reads it.

- [ ] **Step 1: Write the failing tests**

In `test_logs_defaults`, after `compare(store.logsStatus, "")` add:

```qml
    compare(store.logsNote, "")
```

Append to the `// ---- selecting a step (3.1)` section (after `test_a_step_and_an_attempt_are_different_selections`):

```qml
  function test_a_step_with_no_log_says_so_without_an_error() {
    var store = opened(); if (!store) return
    reply(store.logsRunner.current, logsReply("explore text\n"), 0)
    store.selectAttempt(tc.openCard, "worktree", 0, true)
    var before = Date.now()
    reply(store.logsRunner.current, refusalReply(), 0)
    var after = Date.now()
    compare(store.logsText, "")
    compare(store.logsTruncated, false)
    compare(store.logsError, "", "not an error")
    compare(store.logsNote, "This step records no output")
    compare(store.logsLoading, false)
    verify(store.logsFetchedMs >= before && store.logsFetchedMs <= after, "a reply landed: " + store.logsFetchedMs)
    compare(store.amStatus, "ok")
    compare(store.lastError, "")
    store.refreshLogs()
    compare(store.logsNote, "This step records no output", "a refresh keeps the note until its reply")
    reply(store.logsRunner.current, logsReply("worktree text\n"), 0)
    compare(store.logsNote, "", "a good reply clears the note")
    compare(store.logsText, "worktree text")
    compare(store.logsError, "")
  }

  function test_the_note_is_only_for_a_steps_unknown_attempt() {
    var store = opened(); if (!store) return
    var refusal = F.load("logs-follow-refusal.json")
    reply(store.logsRunner.current, logsReply("explore text\n"), 0)
    store.refreshLogs()
    reply(store.logsRunner.current, refusalReply(), 0)
    compare(store.logsError, "UnknownAttemptError: " + refusal.error.message, "an attempt's refusal is an error")
    compare(store.logsNote, "")
    compare(store.logsText, "explore text", "the text is kept")

    store.selectAttempt(tc.openCard, "worktree", 0, true)
    reply(store.logsRunner.current, refusalReply(), 0)
    compare(store.logsNote, "This step records no output")
    store.refreshLogs()
    reply(store.logsRunner.current, JSON.stringify({ ok: false, error: { type: "HelperError", message: "boom" } }) + "\n", 1)
    compare(store.logsError, "HelperError: boom", "another failure of a step is an error")
    compare(store.logsNote, "", "and drops the note")
    store.refreshLogs()
    reply(store.logsRunner.current, refusalReply(), 0)
    compare(store.logsNote, "This step records no output")
    compare(store.logsError, "", "the note replaces the error")
    store.refreshLogs()
    reply(store.logsRunner.current, "not json", 1)
    compare(store.logsError, "The logs snapshot gave no usable result (exit 1).")
    compare(store.logsNote, "", "an unusable reply drops the note")
    // synthetic: an ok:false envelope whose error is not an object
    store.refreshLogs()
    reply(store.logsRunner.current, JSON.stringify({ ok: false, error: "UnknownAttemptError" }) + "\n", 1)
    compare(store.logsNote, "", "only error.type UnknownAttemptError is the note")
    compare(store.logsError, "unknown error")
  }

  // Review Focus 2.
  function test_a_late_step_refusal_after_switching_to_an_attempt_is_dropped() {
    var store = opened(); if (!store) return
    store.selectAttempt(tc.openCard, "worktree", 0, true)
    var stepFetch = store.logsRunner.current
    store.selectAttempt(tc.openCard, "explore", 1)
    var attemptFetch = store.logsRunner.current
    reply(stepFetch, refusalReply(), 0)
    compare(store.logsNote, "", "the step's late reply is dropped")
    reply(attemptFetch, refusalReply(), 0)
    compare(store.logsNote, "", "the attempt's refusal is no note")
    verify(store.logsError.indexOf("UnknownAttemptError: ") === 0, store.logsError)
  }

  function test_another_selection_empties_the_note_and_the_same_step_keeps_it() {
    var store = opened(); if (!store) return
    store.selectAttempt(tc.openCard, "worktree", 0, true)
    reply(store.logsRunner.current, refusalReply(), 0)
    store.selectAttempt(tc.openCard, "worktree", 0, true)
    compare(store.logsNote, "This step records no output", "the same step keeps the note until its reply")
    store.selectAttempt(tc.openCard, "explore", 1)
    compare(store.logsNote, "", "another selection starts without it")
  }

  // Review Focus 5.
  function test_clearing_the_run_clears_the_note() {
    var store = opened(); if (!store) return
    store.selectAttempt(tc.openCard, "worktree", 0, true)
    reply(store.logsRunner.current, refusalReply(), 0)
    compare(store.logsNote, "This step records no output")
    store.selectedRunId = ""
    compare(store.logsNote, "")
    compare(store.selectedAttempt, null)
  }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run.sh core/stores/tst_run_store.qml`
Expected: FAIL for `test_logs_defaults` (`logsNote` undefined, `Actual: undefined Expected: ""`) and each new test above.

- [ ] **Step 3: Write minimal implementation**

In `core/stores/RunStore.qml`, after `property string logsStatus: ""      // the attempt's status when its fetch was launched` add:

```qml
  property string logsNote: ""        // a neutral sentence about the selection's output, not an error; "" when none
```

In `selectAttempt`, the emptying block from Task 2 becomes:

```qml
    if (!old || old.card_id !== cardId || old.phase !== phase || old.attempt !== attempt
        || (old.step === true) !== isStep) {
      store.logsText = ""
      store.logsTruncated = false
      store.logsFetchedMs = 0
      store.logsError = ""
      store.logsNote = ""
    }
```

In `clearLogs`, after `store.logsError = ""` add:

```qml
    store.logsNote = ""
```

Replace `applyLogs` and its comment with:

```qml
  // One logs reply. ok:true replaces the text with its last 200 lines; a
  // step's UnknownAttemptError (am has no log for it) empties the text and
  // sets logsNote "This step records no output", with no error; any other
  // failure keeps the text and only says why. Every reply but the step's
  // UnknownAttemptError leaves logsNote "". Never touches amStatus, runs or
  // lastError: those belong to the snapshot. A reply for an older fetch never
  // gets here (the runner's latest-wins).
  function applyLogs(stdout, exitCode) {
    store.logsLoading = false
    store.logsNote = ""
    var envelope = store.parseEnvelope(stdout)
    if (envelope !== null && envelope.ok === true) {
      var tail = Runs.logTail(envelope.data, 200)
      store.logsText = tail.text
      store.logsTruncated = tail.truncated
      store.logsFetchedMs = Date.now()
      store.logsError = ""
      return
    }
    var sel = store.selectedAttempt
    if (envelope !== null && envelope.ok === false && sel && sel.step === true
        && envelope.error !== null && typeof envelope.error === "object"
        && envelope.error.type === "UnknownAttemptError") {
      store.logsText = ""
      store.logsTruncated = false
      store.logsError = ""
      store.logsNote = "This step records no output"
      store.logsFetchedMs = Date.now()
      return
    }
    if (envelope !== null && envelope.ok === false) {
      store.logsError = Runs.errorText(envelope)
      return
    }
    store.logsError = "The logs snapshot gave no usable result (exit " + exitCode + ")."
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run.sh core/stores/tst_run_store.qml`
Expected: `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(stores): logsNote says a step records no output instead of an error"
```

---

### Task 4: The default opens a step; a step's status change refetches

**Files:**
- Modify: `core/stores/RunStore.qml` -- `openDefaultAttempt` (~line 851), `logsAfterSnapshot` and its comment (~lines 856-869)
- Test: `tests/core/stores/tst_run_store.qml` -- new tests appended to the `// ---- selecting a step (3.1)` section

**Interfaces:**
- Consumes: `store.selectionStatus(run, sel) -> string` (Task 2); `Runs.defaultAttempt(run)` (existing; returns `{card_id, phase, attempt: 0, step: true}` for a started step); test helpers `stepEntry(id, status)`, `refusalReply()` (Task 2), `snapshot(store, entries)` and `argv(proc)` (existing).
- Produces: nothing new for later tasks.

- [ ] **Step 1: Write the failing tests**

Append to the `// ---- selecting a step (3.1)` section:

```qml
  function test_the_default_opens_a_started_step() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([stepEntry("r1", "started")]), 0)
    store.selectedRunId = "r1"
    compare(JSON.stringify(store.selectedAttempt),
            JSON.stringify({ card_id: tc.openCard, phase: "worktree", attempt: 0, step: true }))
    compare(argv(store.logsRunner.current), tc.logsCmd + "r1|" + tc.openCard + "|worktree|0")
    compare(store.logsStatus, "started")
  }

  // Review Focus 4.
  function test_a_run_opened_before_its_first_phase_picks_a_started_step() {
    var store = makeWithProject(rootA); if (!store) return
    // synthetic: the run before any phase exists; shape kept
    var bare = treeEntry("r1", "started")
    var stories = bare.status.stories
    for (var i = 0; i < stories.length; i++) {
      for (var j = 0; j < stories[i].subtasks.length; j++) stories[i].subtasks[j].phases = []
    }
    bare.status.rows = []
    reply(store.snapshotRunner.current, okReply([bare]), 0)
    store.selectedRunId = "r1"
    compare(store.selectedAttempt, null)
    verify(!store.logsRunner.current)
    snapshot(store, [stepEntry("r1", "started")])
    compare(JSON.stringify(store.selectedAttempt),
            JSON.stringify({ card_id: tc.openCard, phase: "worktree", attempt: 0, step: true }))
    compare(argv(store.logsRunner.current), tc.logsCmd + "r1|" + tc.openCard + "|worktree|0")
  }

  function test_a_snapshot_that_changes_the_steps_status_fetches_once() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([stepEntry("r1", "started")]), 0)
    store.selectedRunId = "r1"
    store.selectAttempt(tc.openCard, "worktree", 0, true)
    reply(store.logsRunner.current, refusalReply(), 0)
    compare(store.logsStatus, "started")
    var seq = store.logsRunner.seq
    snapshot(store, [stepEntry("r1", "started")])
    compare(store.logsRunner.seq, seq, "an unchanged step status fetches nothing")
    snapshot(store, [stepEntry("r1", "done")])
    compare(store.logsRunner.seq, seq + 1, "started -> done fetches the step again")
    compare(argv(store.logsRunner.current), tc.logsCmd + "r1|" + tc.openCard + "|worktree|0")
    compare(store.logsStatus, "done")
    snapshot(store, [stepEntry("r1", "done")])
    compare(store.logsRunner.seq, seq + 1, "only once")
  }

  // Review Focus 3.
  function test_a_step_whose_phase_disappears_refetches_once() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([stepEntry("r1", "done")]), 0)
    store.selectedRunId = "r1"
    store.selectAttempt(tc.openCard, "worktree", 0, true)
    compare(store.logsStatus, "done")
    var seq = store.logsRunner.seq
    // synthetic: openCard's worktree phase gone from the snapshot
    var gone = stepEntry("r1", "done")
    gone.status.stories[1].subtasks[1].phases.splice(0, 1)
    snapshot(store, [gone])
    compare(store.logsRunner.seq, seq + 1, "the status moved to \"\"")
    compare(store.logsStatus, "")
    compare(argv(store.logsRunner.current), tc.logsCmd + "r1|" + tc.openCard + "|worktree|0")
    var again = stepEntry("r1", "done")
    again.status.stories[1].subtasks[1].phases.splice(0, 1)
    snapshot(store, [again])
    compare(store.logsRunner.seq, seq + 1, "then nothing")
  }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run.sh core/stores/tst_run_store.qml`
Expected: FAIL for `test_the_default_opens_a_started_step` and `test_a_run_opened_before_its_first_phase_picks_a_started_step` (selection `null`: the default's step flag is dropped), and `test_a_snapshot_that_changes_the_steps_status_fetches_once` (`attemptStatus` gives `""` for the step, so the unchanged snapshot fetches: `Actual: seq+1 Expected: seq`). `test_a_step_whose_phase_disappears_refetches_once` may already pass (with `attemptStatus` a step's status is `""` both before and after the phase goes); it pins Review Focus 3 for the new rule.

- [ ] **Step 3: Write minimal implementation**

In `core/stores/RunStore.qml`, replace `openDefaultAttempt`:

```qml
  // The selected run's default attempt or step, when it has one.
  function openDefaultAttempt() {
    var d = Runs.defaultAttempt(store.runById(store.selectedRunId))
    if (d) store.selectAttempt(d.card_id, d.phase, d.attempt, d.step === true)
  }
```

Replace `logsAfterSnapshot` and its comment:

```qml
  // After every applied snapshot: a selected run with no selection yet gets
  // its default once one exists; otherwise the selection is fetched again
  // only when its status (a step's phase status, an attempt's own) moved since
  // its fetch was launched. Nothing else fetches logs on its own.
  function logsAfterSnapshot() {
    if (store.selectedRunId === "") return
    var sel = store.selectedAttempt
    if (!sel) {
      store.openDefaultAttempt()
      return
    }
    var status = store.selectionStatus(store.runById(store.selectedRunId), sel)
    if (status !== store.logsStatus) store.fetchLogs()
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run.sh core/stores/tst_run_store.qml`
Expected: `0 failed`.

- [ ] **Step 5: Run the whole suite**

Run: `bash tests/run.sh`
Expected: exit 0, no `FAIL` lines, no `TypeError`/`ReferenceError` lines (architecture tests, the run-detail screen tests and `tst_runs_flow.qml`/`tst_runs_real_data.qml` unchanged and green: none of their captures has a started step, so their defaults stay numbered).

- [ ] **Step 6: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(stores): the default opens a started step and a step refetches on its phase status"
```
<!-- task-pipeline: validated -->
