# 5.3 Docs: the four run stores — design

Card: `e7709c33` ("5.3 Docs: the four run stores"). It is a subtask of story `97aa329f` "Retire the
RunStore shims". It is blocked by 5.2 `173b82e2` ("RunStore shims removed"), which has landed on
this branch (`d326d03`). The parent design is
`docs/superpowers/specs/2026-10-05-split-runstore-design.md`, cited below as "P l.N". Line numbers
into `docs/`, `core/`, `ui/` and `tests/` come from this card's start (`d326d03`).

## Purpose

After 5.2, `RunStore` holds no shim and App sets no handle (P l.128-130). `docs/architecture.md`
still describes the shims and still sends the run screens through `app.runs` for members that
`RunControlStore` and `RunDispatchStore` own. This card makes the document say what the code does:

- One top-level bullet per run store in the `core/stores/` list: `RunStore.qml`,
  `RunControlStore.qml`, `RunAlertsStore.qml`, `RunDispatchStore.qml`, in that order. Each says what
  the store owns, which App property composes it (`app.runs`, `app.runControl`, `app.runAlerts`,
  `app.runDispatch`; P l.52-57), what App hands it and which of its signals App routes where
  (P l.72-79).
- The ordering on a snapshot reply is stated once and correctly: App's one `onSnapshotReplied`
  handler calls `app.runControl.settleAfterSnapshot()` when the outcome is `ok`, and only then
  `app.runAlerts.snapshotReplied(…)` (P l.85-86; `core/stores/App.qml:121-124`).
- The UI paragraphs name the store each member really lives on.

The document is the only deliverable. No `.qml`, `.js` or `.py` file outside `tests/architecture/`
changes. A user of the plugin sees nothing different.

## What the code does today (the facts the doc must state)

Read from the files at `d326d03`. The plan's implementer re-reads them before writing, and writes
nothing the files do not show.

### `app.runs` — `RunStore` (`core/stores/App.qml:106-125`)

- App hands it `backendDir`, `projectRoots` (`app.projects.projects` mapped to `{root: root_path,
  name}`, registry order), `project` (the selected project's `root_path`, `""` when none),
  `active` (`app.panelOpen`) and `searchQuery` (`app.nav.searchQuery`).
- App routes `runFilterToggled` and `projectFilterToggled` to putting the cursor home
  (`app.nav.cursorIndex = 0`, `app.nav.scrollOnCursor = false`) and `snapshotReplied(root, outcome,
  previousRuns, runs)` as above. `runsNudged(ids)` is declared (`core/stores/RunStore.qml:121`) and
  App routes it nowhere.
- `RunStore` reads `project` nowhere (`grep -n 'store\.project\b\|onProjectChanged'
  core/stores/RunStore.qml` is empty). App passes `app.runs.project` on to run control and the
  dispatch. So the sentence at `docs/architecture.md:83` "`project` is read only by the run settings
  shims" becomes: the store itself reads no `project`, and a project switch leaves the run list
  alone; App hands `app.runs.project` to `RunControlStore` and `RunDispatchStore`.
- It owns the registry roots, the snapshots, the nudges and the watch, the start-over, `amSchema` /
  `amVersion` and the timers, the reply matching and `snapshotReplied`, the list filters and the
  logs. These are today's paragraphs at `docs/architecture.md:84-90`, and they stay as they are.
- It owns no control, alerts or dispatch member, and no `controlStore` / `alertsStore` /
  `dispatchStore` handle. 5.2's App test pins that.

### `app.runControl` — `RunControlStore` (`core/stores/App.qml:132-142`)

- It gets `backendDir`, `project` (`app.runs.project`), `active` (`app.panelOpen`) and `runs`
  (`app.runs.runs`).
- `refreshRequested(roots)` goes to `app.runs.refresh()` for `"all"`, else to
  `app.runs.requestSnapshot(roots)`.
- `runSettingsSaveFailed(root, patch)` goes to `app.runDispatch.dispatchSaveFailed(root, patch)`.
- The current bullet at `docs/architecture.md:93` already says all of this and how the snapshot
  settles requests. It keeps its text, except where this spec's tests need a change.

### `app.runAlerts` — `RunAlertsStore` (`core/stores/App.qml:148-153`)

- It gets `backendDir`, `active`, `notifyOnEscalation` (`app.runControl.notifyOnEscalation`) and
  `projectRoots` (`app.runs.projectRoots`). App routes none of its signals. Its one input from a
  snapshot is the `snapshotReplied` call in `RunStore`'s handler.
- The current bullet at `docs/architecture.md:94` already says this, and it stays.

### `app.runDispatch` — `RunDispatchStore` (`core/stores/App.qml:161-174`)

- It gets `backendDir`, `project` (`app.runs.project`), `active` (`app.panelOpen`), `runs`
  (`app.runs.runs`) and `runSettings` (`app.runControl.runSettingsOf(app.runs.project)`).
- `refreshRequested(roots)` goes to `app.runs.refresh()` / `requestSnapshot(roots)`,
  `noticeRequested(text)` to `app.runControl.flash(text)`, `runSettingsWanted(root)` to
  `app.runControl.loadRunSettings(root)` and `runSettingsSaveRequested(root, patch)` to
  `app.runControl.saveRunSettings(root, patch)`.
- App does not route `dispatchStarted(runId)`. Panel connects to it on `appStores.runDispatch`
  (`ui/Panel.qml:107-113`): it calls `closeDispatch()`, then `navi.openStartedRun(runId)`.
- Its lifecycle: `onActiveChanged` closes the dispatch when `active` turns false
  (`core/stores/RunDispatchStore.qml:45`). `closeDispatch()` refuses while `starting`
  (`RunDispatchStore.qml:148-152`). `onProjectChanged` resets the dispatch and, when the new project
  is not `""`, emits `runSettingsWanted` (`:49-52`). `tests/core/stores/tst_run_dispatch_store.qml:227-240`
  pins it.
- Today's paragraph at `docs/architecture.md:92` describes the whole dispatch correctly. It becomes a
  top-level `- \`RunDispatchStore.qml\`` bullet after `RunAlertsStore.qml`, opening the same way the
  other two new stores' bullets open ("It never reaches for another store: `App` composes it as
  `app.runDispatch` and hands it …").

### The UI (`ui/`)

Which handle each file reads (`grep -o 'app\(Stores\)\?\.\(runs\|runControl\|runAlerts\|runDispatch\)\b'`):

| file | handles |
|---|---|
| `ui/screens/BoardScreen.qml`, `GraphScreen.qml` | `app.runs` |
| `ui/screens/RunsScreen.qml`, `RunDetailScreen.qml`, `CardDetailScreen.qml`, `ui/Navigator.qml` | `app.runs`, `app.runControl` |
| `ui/Panel.qml`, `ui/Shortcuts.qml` | all four |

The member paths at `d326d03`: `control`, `openCancel`, `confirmCancel`, `closeCancel`,
`cancel*`, `flash` / `flashText`, `stillWaiting*`, `lastControlError*`, `pending`, `refusalOf`,
`notifyOnEscalation` / `setNotifyOnEscalation` are read on `runControl`. `toasts`,
`dismissToast` and `dismissAllToasts` are read on `runAlerts`. `dispatch*`, `openDispatch`,
`closeDispatch`, `setDispatchField`, `dispatchStart` and `retargetToMilestone` are read on
`runDispatch`. `tests/architecture/test_run_store_callers.py` enforces this for `ui/` and `tests/ui/`.

## Required document changes (observable result)

`docs/architecture.md`:

1. **`:83` (`RunStore.qml` bullet).** Name `app.runs` as the App property that composes it. Keep
   the inputs it lists, and add `searchQuery` (`app.nav.searchQuery`) to them. Replace "`project` is read only by the run settings shims" with the
   fact above. Name the signals App routes: `runFilterToggled` / `projectFilterToggled` put the cursor
   home, and `snapshotReplied` goes to run control's `settleAfterSnapshot()` on `ok`, then to
   `app.runAlerts.snapshotReplied`, in that order.
2. **`:84-90`.** Unchanged.
3. **`:91` (the shim paragraph).** Delete it. Keep one fact it carries and move it into the
   `RunStore.qml` bullet: "A snapshot settles requests only through App's `snapshotReplied` route;
   `RunStore` never settles one itself."
4. **`:92` (Dispatch).** Promote it to a top-level `- \`RunDispatchStore.qml\`` bullet placed after
   the `RunAlertsStore.qml` bullet. It opens with what App hands it and routes (above), and
   `dispatchStarted(runId)` is said to be connected by Panel, not App. The rest of the text stays.
5. **`:93`, `:94`.** Keep them. Change only what a test below fails on.
6. **`:155` (`DispatchDialog`).** "the owner passes RunStore's `dispatchState` …" becomes
   "RunDispatchStore's".
7. **`:167` (the run screens paragraph).**
   - "The run screens read `app.runs`" becomes the handles they read: `app.runs` and
     `app.runControl` (see the UI table).
   - "`app.runs.notifyOnEscalation`" becomes `app.runControl.notifyOnEscalation`, and "read through
     the `app.runs` shims" is deleted.
   - "`app.runs.control(action, id)`" becomes `app.runControl.control(action, id)`.
   - "`app.runs.openCancel(runId)`" becomes `app.runControl.openCancel(runId)`.
   - Name `RunToast`'s Dismiss as `app.runAlerts.dismissToast(key)`. Panel calls it at
     `ui/Panel.qml:788`.
8. **`:169` (Panel owns the dispatch).**
   - "`app.runs.openDispatch`" becomes `app.runDispatch.openDispatch`.
   - "`RunStore.retargetToMilestone()`" becomes `RunDispatchStore.retargetToMilestone()`.
   - "closing the panel does not: the store keeps an open dispatch, and the dialog and its chips are
     still there when the panel reopens" contradicts the code and `:92` / `:173`. It becomes: closing
     the panel closes the dispatch too (`RunDispatchStore`'s own `active` reaction), except while
     starting.
9. **`:173`, `:198`, `:263`.** Correct already (they name `RunStore` for the watch, the debounce and
   the list snapshot). No change.

`README.md`: it names no store and no `app.runs` path (`grep -n 'RunStore\|app\.runs' README.md` is
empty), and its Runs and Dispatch bullets (`:154-155`) describe behaviour only. No change. The test
below pins that it stays store-free.

## Error paths

This is a document, so it has no runtime error path. The failure that matters is drift: the
document naming a member on a store that does not own it, naming a removed shim or handle, or
missing an input App binds. Every test below fails on one of those drifts, and the message names
the line and the token.

## Tests

All in one new file, `tests/architecture/test_run_store_docs.py`. **Tier: `tests/architecture`
(pytest, plain Python reading repo files).** The claims are static facts about two repo files and
`core/stores/App.qml`. That tier already holds the run-store caller guard
(`test_run_store_callers.py`), runs in `bash tests/run.sh`'s pytest step, and needs no QML engine.
A QML test cannot read Markdown, and no other tier checks documents. Each test is written first and
fails against `d326d03`'s document. The README test is the exception: it is a guard, and it passes
from the start.

Helpers (in the test file):

- `bullet(name)`: the text of the top-level `- \`<name>\`` bullet of `docs/architecture.md`, from
  its line through every following line that is blank or starts with whitespace, stopping at the
  next line that starts with neither (the next bullet or paragraph). It fails when the bullet is
  missing or appears twice.
- `app_wiring(store_type)`: from `core/stores/App.qml`, the `readonly property <Type> <handle>:
  <Type> {` block (brace-matched). It returns `(handle, bound property names, routed signal
  names)`. A property is a `^\s{4}(\w+):` line that is not `on…`. A signal is an `on<Name>:`
  handler lowercased at its first letter (`onSnapshotReplied` → `snapshotReplied`). It reuses
  `test_run_store_callers.MOVED` / `moved_hits` by import instead of copying them (rule 2 spirit,
  P l.68-71; "no duplicated components").

Tests:

1. `test_each_run_store_has_one_bullet_in_order`: the four bullets exist exactly once, in the order
   `RunStore.qml`, `RunControlStore.qml`, `RunAlertsStore.qml`, `RunDispatchStore.qml`. It fails today
   because there is no `RunDispatchStore.qml` bullet.
2. `test_each_bullet_names_its_app_handle`: `RunStore.qml`'s bullet contains `` `app.runs` `` and
   the others contain `` `app.runControl` ``, `` `app.runAlerts` `` and `` `app.runDispatch` ``
   respectively. The handle is taken from `app_wiring`, not hard-coded. It fails today on `RunStore`
   and `RunDispatchStore`.
3. `test_each_bullet_names_every_input_and_routed_signal_app_wires`: for each store, every bound
   property name and routed signal name from `app_wiring` appears backticked in its bullet
   (`` `name` `` or `` `name(`` …). It fails today on the missing dispatch bullet. `RunStore`'s
   bullet runs through its indented continuation paragraphs `:84-90`, so the names they carry
   count.
4. `test_the_snapshot_reply_settles_control_before_alerts`: `RunStore.qml`'s bullet contains
   `settleAfterSnapshot()` and `app.runAlerts.snapshotReplied`, the first before the second. It fails
   today because `:83-91` names neither in that bullet.
5. `test_run_store_bullet_names_no_member_it_does_not_own`: no `MOVED` member appears backticked as a
   whole token (`` `member` `` or `` `member(`` …) in `RunStore.qml`'s bullet. It fails today on the
   shim lists at `:91`.
6. `test_the_doc_names_no_shim_or_handle`: `docs/architecture.md` contains none of `shim`,
   `controlStore`, `alertsStore`, `dispatchStore` (case-sensitive words). It fails today on `:83`,
   `:91` and `:167`.
7. `test_the_doc_reaches_no_moved_member_through_the_run_store`: `moved_hits(doc)` is empty, and no
   `RunStore.<moved>` or ``RunStore's `<moved>` `` appears. It fails today on `:167`
   (`app.runs.control`, `openCancel`, `notifyOnEscalation`), `:169` (`app.runs.openDispatch`,
   `RunStore.retargetToMilestone`) and `:155` (``RunStore's `dispatchState` ``).
8. `test_the_dispatch_bullet_says_panel_connects_dispatch_started`: `RunDispatchStore.qml`'s bullet
   contains `dispatchStarted` and `Panel`. It fails today because the bullet is missing.
9. `test_the_doc_does_not_say_closing_the_panel_keeps_a_dispatch`: `docs/architecture.md` does not
   contain `the store keeps an open dispatch`. It fails today on `:169`.
10. `test_the_readme_names_no_run_store`: `README.md` contains none of `RunStore`, `RunControlStore`,
    `RunAlertsStore`, `RunDispatchStore`, `app.runs`, `app.runControl`, `app.runAlerts`,
    `app.runDispatch`, `shim`. It passes today, and it keeps the README store-free.
11. `test_the_doc_helpers_flag_and_accept_what_they_should`: a unit test of `bullet()` and
    `app_wiring()` on inline strings. It covers a bullet with indented continuation and blank lines,
    a following unindented paragraph that ends the bullet, a missing bullet and a duplicated one (both
    raise), and a two-store App fragment with a multi-line `on…: {` handler and a `function(…)`
    handler. This follows the pattern of
    `test_run_store_callers.py::test_the_guard_helpers_flag_and_accept_what_they_should`.

Verification: `bash tests/run.sh` is green. The repo wrapper is
`bash /home/mtts/.local/state/agent-manager/verify/vfy-opm.sh`. `tests/architecture/test_layers.py`
and `test_icon_glyphs.py` stay green: the new test file adds no QML and no glyph.

## Inherited constraints

| constraint | source |
|---|---|
| Owners and App properties: `RunStore` = `app.runs`, `RunControlStore` = `app.runControl`, `RunAlertsStore` = `app.runAlerts`, `RunDispatchStore` = `app.runDispatch` | P l.52-57 |
| A store never imports or names a sibling, and wiring is explicit App properties and App-level handlers | P l.46-47 |
| Inputs and routed signals per store | P l.72-79 (the code at `d326d03` governs where it differs: `RunStore` has no `titles`, its nudge signal is `runsNudged`, and `RunDispatchStore` has `active` and no `cardMap` / `projectRoots`) |
| One App handler for `snapshotReplied`: `settleAfterSnapshot()` on `ok`, then `runAlerts.snapshotReplied(…)` | P l.85-86 |
| The shims and handles are gone after the last story | P l.128-130 |
| No behaviour change and no UI change apart from the callers' paths | P l.146-148 |
| `tests/architecture` stays green | P l.105-106 |
| Card: state only what the code does; follow `docs/architecture.md` layering; docstrings and comments state the contract only | card description |

## Out of scope

- Any `.qml`, `.js` or `.py` change outside `tests/architecture/test_run_store_docs.py`. 5.1 owns the
  callers and 5.2 owns the shims. Both have landed.
- Rewriting the store paragraphs that are already correct (`:84-90`, the bodies of `:93` and `:94`,
  and the dispatch body of `:92`), apart from the edits listed above.
- The parent spec's own text, including its stale "Migration (shims)" section and Appendix A. It is
  a design record, not the architecture doc.
- `README.md` prose, which has nothing to change (see above).
- Sibling story work: the members P l.407-416 lists as not present, the later milestones of
  P l.132-142, and `RunStore`'s `runsNudged` having no App route. The doc states that App routes it
  nowhere and does not propose a route.

## Hand-off to the planner

Follow the writing-plans format in this brief. Suggested tasks:

1. **Task 1** writes `tests/architecture/test_run_store_docs.py` with the helpers and their unit
   test (11), then runs it and expects 1-9 to fail and 10-11 to pass.
2. **Task 2** edits the `core/stores/` list of `docs/architecture.md` (changes 1-5) until tests 1-6
   and 8 pass.
3. **Task 3** edits `:155`, `:167` and `:169` (changes 6-8) until 7 and 9 pass, then runs
   `bash tests/run.sh`.

The plan's code blocks show the full test file and the exact replacement sentences, quoted from the
code facts above.
