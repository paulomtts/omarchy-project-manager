# 4.3 Events tab in Run detail (card 62e53e6e) — design

Narrows `docs/superpowers/specs/2026-10-05-run-events-timeline-design.md` ("the parent
spec") to one deliverable: Run detail's bottom area becomes two tabs, Output and Events.
Parent story 55a2dc57 "Events UI". Builds on 4.1 (card 184f6742,
`docs/superpowers/specs/4-1-eventspane-rows-184f6742.md`) and 4.2 (card 61b307a0,
`docs/superpowers/specs/4-2-eventspane-follow-61b307a0.md`), which built
`ui/components/EventsPane.qml` and left its wiring to this card (4.1 spec line 23, 4.2
spec "Out of scope").

## Scope

In scope:

- `core/stores/RunStore.qml`: the tab state (`detailTab`, `setDetailTab`,
  `toggleDetailTab`), reset to Output when the selected run changes.
- `ui/screens/RunDetailScreen.qml`: the tab chips, the Output pane shown only on the
  Output tab, an `EventsPane` bound to `app.runs` shown only on the Events tab, its
  `filterRequested` and `attemptRequested` handled. The header comment states the two-tab
  contract (contract only).
- `ui/Shortcuts.qml`: `handleEventsKey(event)`, the bare `e` that toggles the tabs on Run
  detail; the header comment names it.
- `ui/Panel.qml`: `handleEventsKey` added at the end of the `globalKeys` chain
  (`ui/Panel.qml:407`), and the chain's comment names it.
- Tests, written first (TDD): `tests/core/stores/tst_run_store.qml`,
  `tests/ui/screens/tst_run_detail_screen.qml`, `tests/ui/tst_shortcuts.qml`,
  `tests/ui/tst_runs_flow.qml`.

Out of scope:

- 4.4 (sibling card): `docs/architecture.md` and README, including the key list at
  `docs/architecture.md:94-110` and the RunStore / screen descriptions (4.1 spec line 27).
  This card changes no docs besides this spec and its plan.
- The parent spec's "Load earlier" control, `eventsHasEarlier` and `eventsOldestSeq`
  (parent spec lines 82-84, 96-97, 135): the store has neither and backward paging is not
  built (4.1 spec "Out of scope"; 4.2 spec "Out of scope", first bullet).
- The `am` missing message on the Events tab (parent spec line 155) and the schema banner
  for an `am` too old (line 158). The pane shows what the store's `eventsStatus` /
  `eventsError` say; no `amStatus` branch is added here.
- Any change to `ui/components/EventsPane.qml`, `ChipRow`, `core/domain/*.js`, the
  events fetching in `RunStore.qml` (`selectEvents`, `refreshEvents`, `nudgeEvents`,
  `applyEvents`), `Navigator.qml`, or the Output pane's own behaviour.
- A new store call for "leaving Run detail clears the events": it already happens.
  `Navigator.restoreRunsList` (`ui/Navigator.qml:353`) and `restoreCardFromRun`
  (`ui/Navigator.qml:367`) set `selectedRunId` to `""`, and
  `RunStore.onSelectedRunIdChanged` (`core/stores/RunStore.qml:864`) calls
  `selectEvents()`, which empties `events`, cancels the fetch and sets `eventsStatus`
  to `idle` (`core/stores/RunStore.qml:873-886`). This card pins it with a flow test only.
- Remembering the tab per run, or across Run detail visits.

## Inherited constraints

- "Output and Events share the bottom area as two tabs; `e` toggles them while Run detail
  is open and no modal or text field has the keys" (parent spec lines 139-140).
- "Clicking a row that names an attempt selects it in the tree, loads its output and
  switches to the Output tab; a row without an attempt does nothing" (parent spec lines
  145-146). The pane already emits `attemptRequested` only for a row naming an attempt
  (`ui/components/EventsPane.qml:20-21`, 4.1).
- The Events tab count is the rows held (parent spec lines 147-148). The card refines it:
  the chip carries the rows held plus `eventsDropped` (the store's count of the run's
  events not held, `core/stores/RunStore.qml:132`), standing in for the parent spec's
  `eventsHasEarlier` lower bound.
- "Leaving Run detail or switching runs clears the events and stops fetching" (parent spec
  line 101).
- The existing Output pane stays (parent spec line 36); it keeps working unchanged (card).
- `EventsPane` is wired into `RunDetailScreen.qml` (parent spec line 90). The pane never
  assigns `filter`; its owner does (`ui/components/EventsPane.qml:9-10`;
  `core/stores/RunStore.qml:136`: "the store never sets it").
- Layering (parent spec lines 67-70; `docs/architecture.md:15`): a screen receives `app`
  and never imports `core/stores`; only `Panel`, `Shortcuts`, `Navigator` may.
  `core/stores/*.qml` imports no `QtQuick` (`docs/architecture.md:14`).
- No duplicated components (`tests/architecture/test_layers.py`): the tabs are a
  `ChipRow` (`ui/components/ChipRow.qml`), text is `ThemedText`. No private-use code
  points (`tests/architecture/test_icon_glyphs.py`).
- Key guards follow `handleRunKey`'s (`ui/Shortcuts.qml:62-70`): no modifier at all, the
  right view mode, not under `modalOpen()` (`ui/Shortcuts.qml:49-53`, which counts an open
  dispatch and the cancel confirmation) or the open dropdown.
- Testing: `tests/ui/` covers "the tabs, `e` key, … row click selects the attempt and
  shows Output" (parent spec lines 178-179).
- Comments and docstrings state the contract only, no narrative (card).
- `bash tests/run.sh` green; it fails on qmltestrunner output matching
  `TypeError|ReferenceError|non-existent|Unable to assign|anchors on an item|is not a function`.

## Interface

### RunStore (`core/stores/RunStore.qml`)

```
property string detailTab: "output"   // output | events: Run detail's bottom area
function setDetailTab(tab)            // "output" or "events": sets detailTab, returns true;
                                      // anything else: unchanged, returns false
function toggleDetailTab()            // output -> events, events -> output
```

- `detailTab` is `"output"` at creation.
- Every change of `selectedRunId` (another run, or none) sets `detailTab` to
  `"output"`, in `onSelectedRunIdChanged` alongside `clearLogs` / `selectEvents`.
- Nothing else sets it: a snapshot, a nudge, an events reply, a logs reply,
  `selectAttempt`, a project switch that keeps the selected run, and `eventsFilter`
  leave it alone.

### RunDetailScreen (`ui/screens/RunDetailScreen.qml`)

Inside `runDetailBody`, after the tree and synthetic rows and before `runDetailFlash`,
in this order:

| objectName | what |
|---|---|
| `runTabs` | a `UI.ChipRow`, `chipPrefix: "runTab"`, `active: app.runs.detailTab`, model `[{id: "output", label: "Output"}, {id: "events", label: "Events", count: eventsHeld + app.runs.eventsDropped}]` where `eventsHeld` is `Array.isArray(app.runs.events) ? app.runs.events.length : 0` (a screen property or function; a bare `events.length` throws a TypeError on `null`, which `tests/run.sh` rejects) |
| `runTaboutput` / `runTabevents` | its chips (ChipRow's `chipPrefix + id`); texts `Output` and `Events N` |
| `runOutputPane` | the existing Output column, unchanged inside; `visible: app.runs.detailTab === "output"` |
| `eventsPane` | a `UI.EventsPane` (its own objectName), `visible: app.runs.detailTab === "events"` |

`EventsPane` bindings: `theme: screen.theme`, `rows: app.runs.events`,
`filter: app.runs.eventsFilter`, `dropped: app.runs.eventsDropped`,
`status: app.runs.eventsStatus`, `errorMessage: app.runs.eventsError`; `errorText` and
`maxListHeight` keep the pane's defaults. `width: parent.width`.

Handlers:

- `runTabs.chosen(id)` → `app.runs.setDetailTab(id)`.
- `eventsPane.filterRequested(f)` → `app.runs.eventsFilter = f`.
- `eventsPane.attemptRequested(card, phase, attempt)` →
  `app.runs.selectAttempt(card, phase, attempt)`, then `app.runs.setDetailTab("output")`.

### Shortcuts (`ui/Shortcuts.qml`)

```
function handleEventsKey(event)   // true when it toggled the tabs, else false
```

Returns `false` and changes nothing unless all hold: `event.modifiers === Qt.NoModifier`,
`event.key === Qt.Key_E`, `app.nav.viewMode === "run"`, `!modalOpen()`,
`!app.nav.dropdownOpen`. Otherwise calls `app.runs.toggleDetailTab()` and returns `true`.
The search field is not shown on Run detail (`ui/Panel.qml` ~597, list modes only), so
`viewMode === "run"` is the "no text field has the keys" guard.

### Panel (`ui/Panel.qml:407`)

```
if (sc.handleGlobalKey(event) || sc.handleRunKey(event) || sc.handleDispatchKey(event)
    || sc.handleEventsKey(event)) event.accepted = true
```

## Observable behaviour

### Tabs

- Opening a run shows the Output tab: `runTaboutput` active, `runOutputPane` visible,
  `eventsPane` not visible. Every existing Output-pane test keeps passing unchanged
  (the default tab is Output).
- `runTabevents` reads `Events N`, `N = eventsHeld + eventsDropped` (`eventsHeld` as defined in the table above), updated as either
  changes (`Events 0` with none).
- Clicking `runTabevents` shows the Events tab (`eventsPane` visible, `runOutputPane`
  hidden, Events chip active); clicking `runTaboutput` goes back. Clicking the active chip
  changes nothing.
- The tabs are inside `runDetailBody`, so a run no longer in the snapshot shows the
  existing "This run is no longer in the snapshot" line and no tabs.
- Switching to another run, or leaving Run detail, puts the next Run detail on Output.

### Events tab

- The pane draws the store's rows, filter, dropped count, status and error message as
  4.1/4.2 define; a store change re-renders it (no copy held by the screen).
- A filter chip click in the pane sets `app.runs.eventsFilter`; the pane's active chip
  and shown rows follow from the store.
- A row naming an attempt: `selectAttempt(card, phase, attempt)` is called once with the
  row's values, the tab switches to Output, and the Output heading reads
  `Output · <card> <phase>.<attempt>`; with the real store, `logsRunner` launches for that
  attempt. A row without an attempt does nothing (the pane emits nothing).

### `e` key

- On Run detail, a bare `e` toggles Output ↔ Events, through the panel's key path
  (`keyClick("e")` with the panel focused) as well as `handleEventsKey`.
- Left alone (returns `false`, tab unchanged): Shift+E, Ctrl+E (Ctrl+E stays the memory
  edit chord on a memory, `ui/Shortcuts.qml:35`), any other letter, any view mode but
  `run` (Runs list, board, card), under any modal (`modalOpen()`: cancel confirmation,
  dispatch, delete, …), with the dropdown open.
- On the Runs list a typed `e` still goes into the search field (the key is not
  accepted there).

### Leaving Run detail

- Escape, the left arrow or the crumb back to Runs: `events` is `[]`, `eventsStatus`
  `idle`, no events fetch in flight, `detailTab` `"output"`.

### Error paths (no warning, no throw)

- `events` `null`, not an array, or holding garbage: the Events chip count treats a
  non-array as 0 rows (`Events <eventsDropped>`), the pane handles the rows as 4.1 does.
- `setDetailTab` with anything but `"output"` / `"events"` (including `undefined`,
  `""`, `"Events"`): `detailTab` unchanged, returns `false`.
- `attemptRequested` while `selectAttempt` refuses (no selected run): the tab still
  switches to Output; nothing throws.
- `e` with no run selected while `viewMode === "run"` toggles harmlessly; the store
  resets the tab on the next selection.

## Tests

### Store tier — `tests/core/stores/tst_run_store.qml`

Why this tier: `detailTab` and its reset are store state and store reactions, testable
on a bare `RunStore` with no UI. Use the file's `make()`.

1. `test_the_detail_tab_starts_on_output` — `detailTab === "output"`.
2. `test_set_detail_tab_takes_output_and_events_only` — `setDetailTab("events")` true,
   tab events; `setDetailTab("output")` true; `"Events"`, `""`, `undefined`, `"logs"`
   each false and the tab unchanged.
3. `test_toggle_detail_tab_alternates` — toggle twice: events, then output.
4. `test_a_selection_change_puts_the_tab_back_on_output` — select `r1`, set events,
   select `r2`: output; set events, select `""`: output.
5. `test_nothing_else_moves_the_detail_tab` — selected run, tab events; apply a
   snapshot, set `eventsFilter`, `selectAttempt(...)`, assign `events`: still events.

### Screen tier — `tests/ui/screens/tst_run_detail_screen.qml`

Why this tier: the tab chips, visibility, bindings and handlers are the screen's own
presentation and wiring, driven through a stub `app.runs`. The `runsC` stub gains
`events: []`, `eventsDropped: 0`, `eventsStatus: "idle"`, `eventsError: ""`,
`eventsFilter: "All"`, `detailTab: "output"` and a `setDetailTab(tab)` that records and
assigns (accepting only `output` / `events`). Rows are `{seq, time, level, label, status,
glyph, duration, detail, card, phase, attempt}`; the header comment names the tabs.

6. `test_run_detail_opens_on_the_output_tab` — chips `runTaboutput` (text `Output`) and
   `runTabevents` present; `runOutputPane.visible`, `!eventsPane.visible`.
7. `test_the_events_chip_counts_rows_held_plus_dropped` — 3 rows, `eventsDropped` 40:
   `Events 43`; rows → 5: `Events 45`; none: `Events 0`.
8. `test_the_chips_switch_the_tabs` — tap `runTabevents`: `setDetailTab("events")`
   recorded, `eventsPane` visible, `runOutputPane` hidden; tap `runTaboutput`: back.
9. `test_the_events_pane_shows_the_store_state` — on Events: pane `rows`, `filter`,
   `dropped`, `status`, `errorMessage` equal the stub's; changing `eventsStatus` to
   `error` with a message shows `eventsErrorText`.
10. `test_a_filter_chip_sets_the_store_filter` — tap `eventsFilterChipFailures`:
    `app.runs.eventsFilter === "Failures"`; the pane's `filter` follows.
11. `test_a_row_naming_an_attempt_selects_it_and_shows_output` — row seq 5
    `{card: "t1", phase: "implement", attempt: 1}` on the Events tab, tap `eventsRow5`:
    `selected` is `["t1","implement",1]`, `detailTab === "output"`, `runOutputPane`
    visible, `runOutputHeading.text === "Output · t1 implement.1"`.
12. `test_a_row_without_an_attempt_changes_nothing` — row with `attempt: 0`: tap it,
    `selected` null, tab still events.
13. `test_a_missing_run_shows_no_tabs` — `selectedRunId` not in `runs`: `runDetailBody`
    hidden (so `runTabs` not visible), `runDetailMissing` shows.
14. `test_garbage_events_count_as_none` — `events = null`, `eventsDropped` 2:
    `Events 2`, no warning.

### Shortcut tier — `tests/ui/tst_shortcuts.qml`

Why this tier: the key's guards are `Shortcuts.qml` logic against a real `App` and
`Navigator`, the file's established harness (`make()`, `plain`, `shift`, `ctrl`,
`inRunKeys()`).

15. `test_e_toggles_the_tabs_on_run_detail` — `inRunKeys()`,
    `s.navigator.openRun("run-0000000000a1")`:
    `handleEventsKey(plain(Qt.Key_E))` true → events; again → output.
16. `test_only_a_bare_e_is_the_events_key` — on Run detail: `shift(Key_E)`,
    `ctrl(Key_E)`, `plain(Key_X)` all false, tab output.
17. `test_e_does_nothing_off_run_detail` — Runs list, board, an open card: false, tab
    unchanged.
18. `test_a_modal_or_the_dropdown_swallows_e` — on Run detail:
    `s.app.runs.openCancel("run-0000000000a1")` → false; `s.app.runs.closeCancel()`;
    `s.navigator.toggleDropdown()` → false; tab output each time.

### Flow tier — `tests/ui/tst_runs_flow.qml`

Why this tier: the real `Panel` proves the key reaches `handleEventsKey` through the
key catcher, that the Runs search field still types `e`, and that the real store's
`selectAttempt` launches the logs fetch and leaving clears the events. Use `openDetail()`;
set rows by cancelling `p.app.runs.eventsRunner` and assigning `p.app.runs.events`
(synthetic rows, commented as such).

19. `test_e_switches_run_detail_to_events_and_back` — `openDetail()`, `keyClick("e")`:
    `eventsPane` visible, `runOutputPane` hidden; again: Output.
20. `test_e_in_the_runs_search_types` — on the Runs list, `keyClick("e")`:
    `nav.searchQuery === "e"`, `detailTab` output.
21. `test_an_event_row_click_loads_that_attempt_and_shows_output` — Events tab, a row
    `{card: "t1", phase: "implement", attempt: 1}`, tap it: `logsRunner.current` argv
    ends `t1|implement|1`, `selectedAttempt` matches, Output visible.
22. `test_leaving_run_detail_clears_the_events_and_resets_the_tab` — Events tab with
    rows, `closeRequested()`: `viewMode` runs, `events.length === 0`, `eventsStatus`
    idle, `detailTab` output; reopening the run shows Output.

### Architecture tier (existing, unchanged)

`tests/architecture/test_layers.py` (the screen imports no store; `ChipRow`, not a new
chip row) and `test_icon_glyphs.py`. No new architecture test.

## Acceptance

- Files changed: `core/stores/RunStore.qml`, `ui/screens/RunDetailScreen.qml`,
  `ui/Shortcuts.qml`, `ui/Panel.qml`, the four test files above, this spec and its plan.
- `bash tests/run.sh` is green with no rejected warnings.

---

# 4.3 Events tab in Run detail Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run detail's bottom area becomes two tabs, Output and Events, switched by chips or a bare `e`, with the Events tab showing `EventsPane` bound to the run store.

**Architecture:** The tab is store state (`RunStore.detailTab`, reset on every `selectedRunId` change). `RunDetailScreen` draws a `ChipRow` of the two tabs, shows the existing Output column or a `UI.EventsPane` by `detailTab`, and routes the pane's two signals back to the store. `Shortcuts.handleEventsKey` toggles the tab on Run detail; `Panel` adds it to the end of its `globalKeys` chain.

**Tech Stack:** QML (Qt 6, Quickshell plugin), QtTest via `qmltestrunner`, `bash tests/run.sh` (pytest, then every `tst_*.qml`).

**Spec:** `docs/superpowers/specs/4-3-events-tab-in-run-62e53e6e.md` (copied verbatim above this plan).

## Global Constraints

- A screen receives `app` and never imports `core/stores`; only `Panel`, `Shortcuts`, `Navigator` may (`docs/architecture.md:15`). `core/stores/*.qml` imports no `QtQuick` (`docs/architecture.md:14`).
- No duplicated components (`tests/architecture/test_layers.py`): the tabs are a `ChipRow` (`ui/components/ChipRow.qml`), text is `ThemedText`. No private-use code points (`tests/architecture/test_icon_glyphs.py`).
- Key guards follow `handleRunKey`'s: `event.modifiers === Qt.NoModifier`, the right view mode (`run`), not under `modalOpen()`, not with `app.nav.dropdownOpen`.
- The pane never assigns `filter`; its owner does (`app.runs.eventsFilter = f`).
- `eventsHeld` is `Array.isArray(app.runs.events) ? app.runs.events.length : 0` — never a bare `events.length`.
- Comments and docstrings state the contract only, no narrative.
- Files changed: `core/stores/RunStore.qml`, `ui/screens/RunDetailScreen.qml`, `ui/Shortcuts.qml`, `ui/Panel.qml`, `tests/core/stores/tst_run_store.qml`, `tests/ui/screens/tst_run_detail_screen.qml`, `tests/ui/tst_shortcuts.qml`, `tests/ui/tst_runs_flow.qml`. No change to `ui/components/EventsPane.qml`, `ChipRow`, `core/domain/*.js`, the events fetching in `RunStore.qml`, `Navigator.qml`, or any doc besides the spec and this plan.
- `bash tests/run.sh` green; it fails on qmltestrunner output matching `TypeError|ReferenceError|non-existent|Unable to assign|anchors on an item|is not a function`.

## Review Focus

1. Rows that arrive while the Output tab shows (the pane hidden): switching to Events must open the list at its newest row, following, with no `Jump ↓`. Pinned by `test_rows_that_arrive_while_output_shows_open_at_the_newest` (Task 2).
2. Switching Output → Events → Output must keep the selected attempt, its logs text and the store's filter — a tab switch selects, fetches and filters nothing. Pinned by `test_switching_tabs_keeps_the_output_and_the_filter` (Task 2).
3. Garbage `events` with a `length` (a string, an object `{length: 9}`) must count as 0 held rows, not as its `length`. Pinned by extending `test_garbage_events_count_as_none` (Task 2).
4. Typing `e` into the cancel confirmation's field on Run detail must type it, not toggle the tab. Pinned by `test_e_typed_into_the_cancel_confirmation_on_run_detail_types` (Task 3).
5. `e` on Run detail with no run selected toggles harmlessly, and the next run opened shows Output. Pinned by `test_e_with_no_run_selected_toggles_harmlessly` (Task 3).

## File Structure

- `core/stores/RunStore.qml` — `detailTab`, `setDetailTab`, `toggleDetailTab`; the reset in `onSelectedRunIdChanged`.
- `ui/screens/RunDetailScreen.qml` — `eventsHeld`, the `runTabs` chips, `runOutputPane` visibility, the `EventsPane` and its handlers; header comment.
- `ui/Shortcuts.qml` — `handleEventsKey`; header comment.
- `ui/Panel.qml` — `globalKeys` chain gains `sc.handleEventsKey(event)`; its comment.
- Tests: one file per tier, as listed in the spec.

---

### Task 1: RunStore holds Run detail's tab and resets it on every selection change

**Files:**
- Modify: `core/stores/RunStore.qml:136` (after `eventsFilter`), `core/stores/RunStore.qml:862-867` (`onSelectedRunIdChanged`)
- Test: `tests/core/stores/tst_run_store.qml` (append at the end of the file, before the final `}`)

**Interfaces:**
- Consumes: the file's existing helpers `make()`, `opened(status)`, `reply(proc, text, code)`, `okReply(entries)`, `treeEntry(id, status, root)`, `logsReply(stdout)`, `eventsReply(events, lastSeq, total)`, `attemptEvents(first, n)`, `tc.doneCard`.
- Produces: `RunStore.detailTab: string` (`"output"` | `"events"`), `RunStore.setDetailTab(tab) -> bool`, `RunStore.toggleDetailTab() -> void`. Tasks 2 and 3 call these exact names.

- [ ] **Step 1: Write the failing tests**

Append to `tests/core/stores/tst_run_store.qml`, just before its last line (`}`):

```qml
  // ---- Run detail's tab (4.3)

  // 1
  function test_the_detail_tab_starts_on_output() {
    var store = make(); if (!store) return
    compare(store.detailTab, "output")
  }

  // 2
  function test_set_detail_tab_takes_output_and_events_only() {
    var store = make(); if (!store) return
    compare(store.setDetailTab("events"), true)
    compare(store.detailTab, "events")
    compare(store.setDetailTab("output"), true)
    compare(store.detailTab, "output")
    store.setDetailTab("events")
    var bad = ["Events", "", undefined, "logs", null, 1]
    for (var i = 0; i < bad.length; i++) {
      compare(store.setDetailTab(bad[i]), false, String(bad[i]))
      compare(store.detailTab, "events", "unchanged by " + String(bad[i]))
    }
  }

  // 3
  function test_toggle_detail_tab_alternates() {
    var store = make(); if (!store) return
    store.toggleDetailTab()
    compare(store.detailTab, "events")
    store.toggleDetailTab()
    compare(store.detailTab, "output")
  }

  // 4
  function test_a_selection_change_puts_the_tab_back_on_output() {
    var store = make(); if (!store) return
    store.selectedRunId = "r1"
    store.setDetailTab("events")
    store.selectedRunId = "r2"
    compare(store.detailTab, "output", "another run")
    store.setDetailTab("events")
    store.selectedRunId = ""
    compare(store.detailTab, "output", "no run")
  }

  // 5
  function test_nothing_else_moves_the_detail_tab() {
    var store = opened(); if (!store) return
    store.setDetailTab("events")
    store.refresh()
    reply(store.snapshotRunner.current, okReply([treeEntry("r1", "done")]), 0)
    compare(store.selectedRunId, "r1", "the snapshot kept the selection")
    compare(store.detailTab, "events", "a snapshot")
    store.eventsFilter = "Failures"
    compare(store.detailTab, "events", "the filter")
    store.selectAttempt(tc.doneCard, "spec", 1)
    reply(store.logsRunner.current, logsReply("3 passed\n"), 0)
    compare(store.detailTab, "events", "an attempt and its logs")
    reply(store.eventsRunner.current, eventsReply(attemptEvents(8, 3), 10, 10), 0)
    compare(store.detailTab, "events", "an events reply")
    // synthetic: rows as a reply would leave them.
    store.events = [{ seq: 4 }]
    store.runsNudged(["r1"])
    compare(store.detailTab, "events", "rows and a nudge")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_run_store`
Expected: FAIL — the five new tests fail (`detailTab` is `undefined`; `setDetailTab` / `toggleDetailTab` "is not a function"), and the script exits non-zero.

- [ ] **Step 3: Implement the tab state**

In `core/stores/RunStore.qml`, directly after the `eventsFilter` line (line 136):

```qml
  property string eventsFilter: "All" // All | Phases | Failures, read by RunEvents.filterRows; the store never sets it
  // Run detail's bottom area: output | events. Every selectedRunId change
  // sets it to output; only setDetailTab and toggleDetailTab change it otherwise.
  property string detailTab: "output"
```

Replace `onSelectedRunIdChanged` and its comment (lines 862-867) with:

```qml
  // Another run (or none): the pane starts over on that run's default
  // attempt, the events start over (selectEvents) and the tab is Output.
  onSelectedRunIdChanged: {
    store.clearLogs()
    if (store.selectedRunId !== "") store.openDefaultAttempt()
    store.selectEvents()
    store.detailTab = "output"
  }

  // "output" or "events": sets detailTab and returns true; anything else
  // leaves it and returns false.
  function setDetailTab(tab) {
    if (tab !== "output" && tab !== "events") return false
    store.detailTab = tab
    return true
  }

  // output -> events, events -> output.
  function toggleDetailTab() {
    store.detailTab = store.detailTab === "events" ? "output" : "events"
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_run_store`
Expected: PASS — `Totals: N passed, 0 failed`, no rejected warning lines, exit 0.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(run-store): Run detail's tab, reset to Output on every selection change"
```

---

### Task 2: RunDetailScreen draws the Output / Events tabs and wires EventsPane

**Files:**
- Modify: `ui/screens/RunDetailScreen.qml` — header comment (lines 10-18), a new `eventsHeld` property after `nowMs` (line 37), `runTabs` and the `EventsPane` inside `runDetailBody` around `runOutputPane` (lines 213-283)
- Test: `tests/ui/screens/tst_run_detail_screen.qml` — header comment, the `runsC` stub (lines 23-54), new tests appended before the final `}`

**Interfaces:**
- Consumes (Task 1): `app.runs.detailTab: string`, `app.runs.setDetailTab(tab) -> bool`. Existing store fields: `app.runs.events: array|any`, `eventsDropped: int`, `eventsStatus: string`, `eventsError: string`, `eventsFilter: string`, `selectAttempt(card, phase, attempt)`. `UI.EventsPane` (props `theme, rows, filter, dropped, status, errorMessage`; signals `filterRequested(string filter)`, `attemptRequested(string card, string phase, int attempt)`; objectName `eventsPane`; its rows are `eventsRow<seq>`, its chips `eventsFilterChip<id>`, its list `eventsList`, its jump `eventsJump`, its error line `eventsErrorText`).
- Produces: objectNames `runTabs`, `runTaboutput`, `runTabevents`, `runOutputPane` (now tab-gated), `eventsPane` inside `runDetailView`; screen property `eventsHeld: int`. Task 3's flow tests find these names.

- [ ] **Step 1: Extend the stub and write the failing tests**

In `tests/ui/screens/tst_run_detail_screen.qml`, replace the header comment (lines 1-6) with:

```qml
// tests/ui/screens/tst_run_detail_screen.qml
// ui/screens/RunDetailScreen.qml on its own: the header, the story > subtask >
// attempt tree with its bookkeeping rows, the Output / Events tabs with the
// output pane and the events pane, and the missing-run line. A stub app: a
// REAL NavigationStore, a plain object carrying the RunStore properties the
// screen reads (with recorders for selectAttempt, refreshLogs and
// setDetailTab), and a board whose cardMap lends titles and brd statuses.
```

In the `runsC` stub, directly after `function refreshLogs() { rs.refreshed += 1 }`, add:

```qml
      // The events and the tab (4.3). setDetailTab records every call and,
      // as the store does, takes only output and events.
      property var events: []
      property int eventsDropped: 0
      property string eventsStatus: "idle"
      property string eventsError: ""
      property string eventsFilter: "All"
      property string detailTab: "output"
      property var tabCalls: []
      function setDetailTab(tab) {
        rs.tabCalls = rs.tabCalls.concat([tab])
        if (tab !== "output" && tab !== "events") return false
        rs.detailTab = tab
        return true
      }
```

Append before the file's final `}`:

```qml
  // ---- the Output / Events tabs (4.3)

  // A complete row as RunEvents.eventRow returns it; `fields` overrides.
  function eventRow(seq, fields) {
    var row = { seq: seq, time: "12:00:00", level: "attempt", label: "row " + seq, status: "done",
                glyph: "done", duration: "", detail: "", card: "card-" + seq, phase: "implement",
                attempt: 1 }
    for (var key in fields) row[key] = fields[key]
    return row
  }

  function rowsUpTo(n) {
    var rows = []
    for (var i = 1; i <= n; i++) rows.push(eventRow(i, {}))
    return rows
  }

  function shown(s, name) { return H.find(s.screen, name).visible }

  // 6
  function test_run_detail_opens_on_the_output_tab() {
    var s = make(detail()); if (!s) return
    var output = H.find(s.screen, "runTaboutput")
    verify(output, "the Output chip")
    compare(output.text, "Output")
    compare(output.active, true)
    verify(H.find(s.screen, "runTabevents"), "the Events chip")
    compare(H.find(s.screen, "runTabevents").active, false)
    compare(shown(s, "runOutputPane"), true)
    compare(shown(s, "eventsPane"), false)
  }

  // 7
  function test_the_events_chip_counts_rows_held_plus_dropped() {
    var s = make(detail()); if (!s) return
    compare(H.find(s.screen, "runTabevents").text, "Events 0", "none")
    s.runs.events = rowsUpTo(3)
    s.runs.eventsDropped = 40
    compare(H.find(s.screen, "runTabevents").text, "Events 43")
    s.runs.events = rowsUpTo(5)
    compare(H.find(s.screen, "runTabevents").text, "Events 45")
    s.runs.events = []
    s.runs.eventsDropped = 0
    compare(H.find(s.screen, "runTabevents").text, "Events 0")
  }

  // 8
  function test_the_chips_switch_the_tabs() {
    var s = make(detail()); if (!s) return
    tap(H.find(s.screen, "runTabevents"))
    compare(s.runs.tabCalls.join(","), "events")
    compare(shown(s, "eventsPane"), true)
    compare(shown(s, "runOutputPane"), false)
    compare(H.find(s.screen, "runTabevents").active, true)
    tap(H.find(s.screen, "runTabevents"))
    compare(s.runs.detailTab, "events", "the active chip changes nothing")
    compare(shown(s, "eventsPane"), true)
    tap(H.find(s.screen, "runTaboutput"))
    compare(s.runs.detailTab, "output")
    compare(shown(s, "runOutputPane"), true)
    compare(shown(s, "eventsPane"), false)
    compare(H.find(s.screen, "runTaboutput").active, true)
  }

  // 9
  function test_the_events_pane_shows_the_store_state() {
    var s = make(detail()); if (!s) return
    s.runs.setDetailTab("events")
    s.runs.events = rowsUpTo(2)
    s.runs.eventsDropped = 3
    s.runs.eventsStatus = "ok"
    var pane = H.find(s.screen, "eventsPane")
    compare(JSON.stringify(pane.rows), JSON.stringify(s.runs.events))
    compare(pane.filter, "All")
    compare(pane.dropped, 3)
    compare(pane.status, "ok")
    compare(pane.errorMessage, "")
    verify(H.find(pane, "eventsRow2"), "the store's rows are drawn")
    compare(H.find(pane, "eventsErrorText").visible, false)
    s.runs.eventsStatus = "error"
    s.runs.eventsError = "AmMissing: am is not on PATH."
    compare(pane.status, "error")
    compare(pane.errorMessage, "AmMissing: am is not on PATH.")
    compare(H.find(pane, "eventsErrorText").visible, true)
  }

  // 10
  function test_a_filter_chip_sets_the_store_filter() {
    var s = make(detail()); if (!s) return
    s.runs.setDetailTab("events")
    s.runs.events = [eventRow(1, { level: "phase", glyph: "dead", status: "failed" }), eventRow(2, {})]
    var pane = H.find(s.screen, "eventsPane")
    tap(H.find(pane, "eventsFilterChipFailures"))
    compare(s.runs.eventsFilter, "Failures")
    compare(pane.filter, "Failures", "the pane follows the store")
    compare(H.find(pane, "eventsFilterChipFailures").active, true)
  }

  // 11
  function test_a_row_naming_an_attempt_selects_it_and_shows_output() {
    var s = make(detail()); if (!s) return
    s.runs.setDetailTab("events")
    s.runs.events = [eventRow(5, { card: "t1", phase: "implement", attempt: 1 })]
    wait(30)
    tap(H.find(s.screen, "eventsRow5"))
    compare(s.runs.selected.join("|"), "t1|implement|1")
    compare(s.runs.detailTab, "output")
    compare(shown(s, "runOutputPane"), true)
    compare(shown(s, "eventsPane"), false)
    compare(H.find(s.screen, "runOutputHeading").text, "Output · t1 implement.1")
  }

  // 12
  function test_a_row_without_an_attempt_changes_nothing() {
    var s = make(detail()); if (!s) return
    s.runs.setDetailTab("events")
    s.runs.events = [eventRow(6, { attempt: 0 })]
    wait(30)
    tap(H.find(s.screen, "eventsRow6"))
    compare(s.runs.selected, null)
    compare(s.runs.detailTab, "events")
    compare(s.runs.tabCalls.join(","), "events", "no tab call from the row")
  }

  // 13
  function test_a_missing_run_shows_no_tabs() {
    var s = make(detail(), "run-gone"); if (!s) return
    compare(shown(s, "runDetailBody"), false)
    compare(shown(s, "runTabs"), false)
    compare(shown(s, "runDetailMissing"), true)
  }

  // 14 and Review Focus 3
  function test_garbage_events_count_as_none() {
    failOnWarning(/TypeError|ReferenceError|is not a function|Unable to assign/)
    var s = make(detail()); if (!s) return
    s.runs.eventsDropped = 2
    s.runs.events = null
    compare(H.find(s.screen, "runTabevents").text, "Events 2", "null")
    s.runs.events = "abcdefghi"
    compare(H.find(s.screen, "runTabevents").text, "Events 2", "a string")
    s.runs.events = { length: 9 }
    compare(H.find(s.screen, "runTabevents").text, "Events 2", "an object with a length")
    s.runs.setDetailTab("events")
    compare(shown(s, "eventsPane"), true)
  }

  // Review Focus 1
  function test_rows_that_arrive_while_output_shows_open_at_the_newest() {
    var s = make(detail()); if (!s) return
    s.runs.events = rowsUpTo(60)
    wait(30)
    tap(H.find(s.screen, "runTabevents"))
    wait(30)
    var pane = H.find(s.screen, "eventsPane")
    var list = H.find(pane, "eventsList")
    verify(list.contentHeight > list.height, "the list scrolls")
    compare(pane.following, true)
    verify(Math.abs(list.contentY - (list.originY + list.contentHeight - list.height)) <= 1, "at the newest row")
    compare(H.find(pane, "eventsJump").visible, false)
  }

  // Review Focus 2
  function test_switching_tabs_keeps_the_output_and_the_filter() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    s.runs.logsText = "3 passed"
    s.runs.eventsFilter = "Failures"
    tap(H.find(s.screen, "runTabevents"))
    tap(H.find(s.screen, "runTaboutput"))
    compare(H.find(s.screen, "runOutputHeading").text, "Output · t1 implement.2")
    compare(H.find(s.screen, "runOutputText").text, "3 passed")
    compare(s.runs.selected, null, "no attempt was selected")
    compare(s.runs.refreshed, 0, "nothing was fetched")
    compare(s.runs.eventsFilter, "Failures")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_run_detail_screen`
Expected: FAIL — the new tests fail (`runTaboutput` / `eventsPane` not found, so `verify` fails or a `TypeError: Cannot read property 'text' of null` is printed); the existing tests still pass.

- [ ] **Step 3: Implement the tabs and the pane**

In `ui/screens/RunDetailScreen.qml`, replace the header comment (lines 10-18) with:

```qml
// One am run (the "run" view): a header with its state, milestone, branch
// prefix and base and lease; its story > subtask > phase > attempt tree, with
// the orchestrator's own Integrate / Bases / Base rows when it has them; and a
// bottom area of two tabs, app.runs.detailTab, chosen by the Output / Events
// chips. Output holds ONE attempt's `am logs` snapshot -- labelled with its
// age, never presented as a live tail. Events is the run's event timeline
// (EventsPane over app.runs.events); its filter chips set app.runs.eventsFilter,
// and a row naming an attempt selects that attempt and shows Output. The
// Events chip counts the rows held plus app.runs.eventsDropped. Run state
// always comes from am (the run store), never from a brd status; brd's board
// only lends titles and dims the cards it has closed. It reads the run store
// and asks it to show another attempt or tab or fetch again; it owns no state
// of its own. Ages are read against the clock when a logs reply lands or a
// snapshot replaces the runs: no timer.
```

After the `nowMs` property (line 37), add:

```qml
  // The rows the store holds; 0 when `events` is not an array.
  readonly property int eventsHeld: Array.isArray(screen.app.runs.events) ? screen.app.runs.events.length : 0
```

Inside `runDetailBody`, between the `SyntheticRow` `Repeater` and the `Column { objectName: "runOutputPane" ...`, add:

```qml
    UI.ChipRow {
      objectName: "runTabs"
      width: parent.width
      theme: screen.theme
      chipPrefix: "runTab"
      active: screen.app.runs.detailTab
      model: [{ id: "output", label: "Output" },
              { id: "events", label: "Events", count: screen.eventsHeld + screen.app.runs.eventsDropped }]
      onChosen: function(id) { screen.app.runs.setDetailTab(id) }
    }
```

On the `runOutputPane` `Column`, directly after `spacing: Style.space(4)`, add one line (nothing else inside it changes):

```qml
      visible: screen.app.runs.detailTab === "output"
```

After the `runOutputPane` `Column`'s closing `}` and before the `// Why the last run key was refused` comment, add:

```qml
    UI.EventsPane {
      width: parent.width
      visible: screen.app.runs.detailTab === "events"
      theme: screen.theme
      rows: screen.app.runs.events
      filter: screen.app.runs.eventsFilter
      dropped: screen.app.runs.eventsDropped
      status: screen.app.runs.eventsStatus
      errorMessage: screen.app.runs.eventsError
      onFilterRequested: function(f) { screen.app.runs.eventsFilter = f }
      onAttemptRequested: function(card, phase, attempt) {
        screen.app.runs.selectAttempt(card, phase, attempt)
        screen.app.runs.setDetailTab("output")
      }
    }
```

(`EventsPane` sets its own `objectName: "eventsPane"`; do not set one here.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_run_detail_screen`
Expected: PASS — `Totals: N passed, 0 failed`, no rejected warning lines. If `test_rows_that_arrive_while_output_shows_open_at_the_newest` alone fails, the hidden pane's list did not lay out its rows; do not change `EventsPane.qml` (out of scope) — stop and report the failure with its output.

- [ ] **Step 5: Run the architecture tests**

Run: `uv run --with pytest python3 -m pytest tests/architecture -q` (or `python3 -m pytest tests/architecture -q` when pytest is importable)
Expected: PASS (the screen imports no store; the tabs are a `ChipRow`; no private-use glyph).

- [ ] **Step 6: Commit**

```bash
git add ui/screens/RunDetailScreen.qml tests/ui/screens/tst_run_detail_screen.qml
git commit -m "feat(run-detail): Output / Events tabs, with EventsPane bound to the run store"
```

---

### Task 3: A bare `e` toggles the tabs on Run detail, through the panel's key path

**Files:**
- Modify: `ui/Shortcuts.qml` — header comment (lines 4-6), new `handleEventsKey` after `handleDispatchKey` (after line 101)
- Modify: `ui/Panel.qml:401-409` — the `globalKeys` comment and chain
- Test: `tests/ui/tst_shortcuts.qml` (append before the final `}`), `tests/ui/tst_runs_flow.qml` (append before the final `}`)

**Interfaces:**
- Consumes (Task 1): `app.runs.detailTab`, `app.runs.setDetailTab(tab)`, `app.runs.toggleDetailTab()`. (Task 2): objectNames `eventsPane`, `runOutputPane`, `runOutputHeading`, `eventsRow<seq>` inside the Panel. Existing: `Shortcuts.modalOpen()`, `navigator.openRun(id)`, `navigator.toggleDropdown()`, `navigator.goBack()`, `navigator.activateCrumb(i)`, `shortcuts.closeRequested()`, `shortcuts.handleMove(dx, dy)`, `app.runs.openCancel(id)`, `app.runs.closeCancel()`, `app.runs.eventsRunner` (a HelperRunner: `cancel()`, `busy`), `app.runs.logsRunner.current.command`.
- Produces: `Shortcuts.handleEventsKey(event) -> bool`.

- [ ] **Step 1: Write the failing shortcut tests**

Append to `tests/ui/tst_shortcuts.qml`, before its final `}`:

```qml
  // ---- e: Run detail's Output / Events tabs (4.3)

  // 15
  function test_e_toggles_the_tabs_on_run_detail() {
    var s = inRunKeys(); if (!s) return
    s.navigator.openRun("run-0000000000a1")
    compare(s.app.nav.viewMode, "run")
    compare(s.app.runs.detailTab, "output")
    compare(s.handleEventsKey(plain(Qt.Key_E)), true)
    compare(s.app.runs.detailTab, "events")
    compare(s.handleEventsKey(plain(Qt.Key_E)), true)
    compare(s.app.runs.detailTab, "output")
  }

  // 16
  function test_only_a_bare_e_is_the_events_key() {
    var s = inRunKeys(); if (!s) return
    s.navigator.openRun("run-0000000000a1")
    compare(s.handleEventsKey(shift(Qt.Key_E)), false, "Shift+E")
    compare(s.handleEventsKey(ctrl(Qt.Key_E)), false, "Ctrl+E is the memory edit chord")
    compare(s.handleEventsKey(plain(Qt.Key_X)), false, "another letter")
    compare(s.app.runs.detailTab, "output")
  }

  // 17
  function test_e_does_nothing_off_run_detail() {
    var s = inRunKeys(); if (!s) return
    s.app.runs.setDetailTab("events")
    compare(s.app.nav.viewMode, "runs")
    compare(s.handleEventsKey(plain(Qt.Key_E)), false, "runs")
    s.navigator.showSection("board")
    compare(s.app.nav.viewMode, "board")
    compare(s.handleEventsKey(plain(Qt.Key_E)), false, "board")
    s.app.board.applyTreeData([card("m1", "Milestone", "todo")])
    wait(20)
    s.navigator.openCard("m1")
    compare(s.app.nav.viewMode, "entry")
    compare(s.handleEventsKey(plain(Qt.Key_E)), false, "entry")
    compare(s.app.runs.detailTab, "events", "unchanged")
  }

  // 18
  function test_a_modal_or_the_dropdown_swallows_e() {
    var s = inRunKeys(); if (!s) return
    s.navigator.openRun("run-0000000000a1")
    compare(s.app.runs.openCancel("run-0000000000a1"), true)
    compare(s.handleEventsKey(plain(Qt.Key_E)), false, "the cancel confirmation")
    s.app.runs.closeCancel()
    s.app.runs.dispatchState = "ready"
    compare(s.handleEventsKey(plain(Qt.Key_E)), false, "an open dispatch")
    s.app.runs.dispatchState = "idle"
    s.navigator.toggleDropdown()
    compare(s.app.nav.dropdownOpen, true)
    compare(s.handleEventsKey(plain(Qt.Key_E)), false, "the dropdown")
    compare(s.app.runs.detailTab, "output")
  }

  // Review Focus 5
  function test_e_with_no_run_selected_toggles_harmlessly() {
    failOnWarning(/TypeError|ReferenceError|is not a function/)
    var s = inRunKeys(); if (!s) return
    s.navigator.openRun("run-0000000000a1")
    s.app.runs.selectedRunId = ""
    compare(s.app.nav.viewMode, "run")
    compare(s.handleEventsKey(plain(Qt.Key_E)), true)
    compare(s.app.runs.detailTab, "events")
    s.navigator.goBack()
    s.navigator.openRun("run-0000000000b2")
    compare(s.app.runs.detailTab, "output", "the next run opens on Output")
  }
```

- [ ] **Step 2: Run them to verify they fail**

Run: `bash tests/run.sh tst_shortcuts`
Expected: FAIL — the five new tests fail with `TypeError: Property 'handleEventsKey' of object ... is not a function`.

- [ ] **Step 3: Implement `handleEventsKey`**

In `ui/Shortcuts.qml`, replace the header comment's first three lines (lines 4-6) with:

```qml
// Every key the panel reacts to, in one place: the Ctrl chords, the run keys
// (p / r / c), the dispatch key (d), the events key (e), the Escape chain, the
// arrows the key catcher reports, and the search field's own keys.
```

After `handleDispatchKey`'s closing `}` (line 101), add:

```qml
  // e with no modifier at all switches Run detail's bottom area between
  // Output and Events. Returns true when it did. Anywhere but Run detail,
  // under a modal or the open dropdown, the letter is left alone; Run detail
  // shows no search field, so no text field has the keys there.
  function handleEventsKey(event) {
    if (event.modifiers !== Qt.NoModifier || event.key !== Qt.Key_E) return false
    if (keys.app.nav.viewMode !== "run" || keys.modalOpen() || keys.app.nav.dropdownOpen) return false
    keys.app.runs.toggleDetailTab()
    return true
  }
```

- [ ] **Step 4: Run them to verify they pass**

Run: `bash tests/run.sh tst_shortcuts`
Expected: PASS — `Totals: N passed, 0 failed`, no rejected warning lines.

- [ ] **Step 5: Write the flow tests**

Append to `tests/ui/tst_runs_flow.qml`, before its final `}`:

```qml
  // ---- the Output / Events tabs (4.3)

  // A complete row as RunEvents.eventRow returns it; `fields` overrides.
  function eventRow(seq, fields) {
    var row = { seq: seq, time: "12:00:00", level: "attempt", label: "row " + seq, status: "done",
                glyph: "done", duration: "", detail: "", card: "card-" + seq, phase: "implement",
                attempt: 1 }
    for (var key in fields) row[key] = fields[key]
    return row
  }

  // The run's events fetch is disarmed and `rows` held, as a reply would
  // leave them. synthetic: the rows are the test's.
  function holdRows(p, rows) {
    p.app.runs.eventsRunner.cancel()
    p.app.runs.events = rows
    p.app.runs.eventsStatus = "ok"
  }

  // 19
  function test_e_switches_run_detail_to_events_and_back() {
    var p = openDetail(); if (!p) return
    H.find(p, "keyCatcher").forceActiveFocus()
    keyClick("e")
    compare(p.app.runs.detailTab, "events")
    compare(H.find(p, "eventsPane").visible, true)
    compare(H.find(p, "runOutputPane").visible, false)
    keyClick("e")
    compare(p.app.runs.detailTab, "output")
    compare(H.find(p, "eventsPane").visible, false)
    compare(H.find(p, "runOutputPane").visible, true)
  }

  // 20
  function test_e_in_the_runs_search_types() {
    var p = make(); if (!p) return
    p.navigator.showSection("runs")
    wait(50)
    var field = H.find(p, "searchField")
    field.forceActiveFocus()
    keyClick("e")
    compare(field.text, "e")
    compare(p.app.nav.searchQuery, "e")
    compare(p.app.runs.detailTab, "output")
  }

  // 21. The panel's popup is a test stub, so the row's own activated() stands
  // in for the click; the screen tier clicks it.
  function test_an_event_row_click_loads_that_attempt_and_shows_output() {
    var p = openDetail(); if (!p) return
    compare(p.app.runs.selectedAttempt.attempt, 2, "the default attempt")
    holdRows(p, [eventRow(5, { card: "t1", phase: "implement", attempt: 1 })])
    p.app.runs.setDetailTab("events")
    wait(50)
    var row = H.find(p, "eventsRow5")
    verify(row, "the row is drawn")
    row.activated()
    compare(p.app.runs.logsRunner.current.command.slice(2).join("|"), "/home/u/a|run-0000000000e5|t1|implement|1")
    compare(JSON.stringify(p.app.runs.selectedAttempt), JSON.stringify({ card_id: "t1", phase: "implement", attempt: 1 }))
    compare(p.app.runs.detailTab, "output")
    compare(H.find(p, "runOutputPane").visible, true)
    compare(H.find(p, "runOutputHeading").text, "Output · t1 implement.1")
  }

  // 22. The events fetch is left in flight: leaving must stop it.
  function test_leaving_run_detail_clears_the_events_and_resets_the_tab_data() {
    return [{ tag: "escape" }, { tag: "left-arrow" }, { tag: "crumb" }]
  }

  function test_leaving_run_detail_clears_the_events_and_resets_the_tab(data) {
    var p = openDetail(); if (!p) return
    compare(p.app.runs.eventsRunner.busy, true, "the run's events are being fetched")
    // synthetic: rows as a reply would leave them.
    p.app.runs.events = [eventRow(5, {}), eventRow(6, {})]
    p.app.runs.setDetailTab("events")
    if (data.tag === "escape") p.shortcuts.closeRequested()
    else if (data.tag === "left-arrow") p.shortcuts.handleMove(-1, 0)
    else p.navigator.activateCrumb(0)
    compare(p.app.nav.viewMode, "runs")
    compare(p.app.runs.events.length, 0)
    compare(p.app.runs.eventsStatus, "idle")
    compare(p.app.runs.eventsRunner.busy, false, "no events fetch in flight")
    compare(p.app.runs.detailTab, "output")
    p.navigator.openRun("run-0000000000e5")
    wait(50)
    compare(H.find(p, "runOutputPane").visible, true)
    compare(H.find(p, "eventsPane").visible, false)
  }

  // Review Focus 4
  function test_e_typed_into_the_cancel_confirmation_on_run_detail_types() {
    var p = openDetail(); if (!p) return
    H.find(p, "keyCatcher").forceActiveFocus()
    keyClick("c")
    compare(p.app.runs.cancelOpen, true)
    wait(50)
    compare(p.focusItem.objectName, "runCancelField")
    keyClick("e")
    compare(p.app.runs.cancelText, "e")
    compare(p.app.runs.detailTab, "output")
  }
```

- [ ] **Step 6: Run the flow tests to verify the key path fails**

Run: `bash tests/run.sh tst_runs_flow`
Expected: FAIL — `test_e_switches_run_detail_to_events_and_back` fails (`detailTab` stays `output`: the panel's chain does not call `handleEventsKey` yet). Tests 20, 21, 22 and the cancel-field test already pass: they pin behaviour Tasks 1-2 built and the store already had (the leaving reset, the real `selectAttempt` fetch, the search field typing).

- [ ] **Step 7: Wire the key into the panel**

In `ui/Panel.qml`, replace lines 401-409:

```qml
    // The Ctrl chords, then the run keys (p / r / c on the Runs list and Run
    // detail), then d (the dispatch, on the board list and a card), then e
    // (Output / Events on Run detail). An accepted key is not typed into the
    // search field.
    Item {
      id: globalKeys
      Keys.onPressed: function(event) {
        if (sc.handleGlobalKey(event) || sc.handleRunKey(event) || sc.handleDispatchKey(event)
            || sc.handleEventsKey(event)) event.accepted = true
      }
    }
```

- [ ] **Step 8: Run the flow tests to verify they pass**

Run: `bash tests/run.sh tst_runs_flow`
Expected: PASS — `Totals: N passed, 0 failed`, no rejected warning lines.

- [ ] **Step 9: Run the whole suite**

Run: `bash tests/run.sh`
Expected: every pytest test passes; every `== tests/...tst_*.qml` block shows `Totals: N passed, 0 failed, ...`; no line matching `TypeError|ReferenceError|non-existent|Unable to assign|anchors on an item|is not a function`; exit status 0.

- [ ] **Step 10: Commit**

```bash
git add ui/Shortcuts.qml ui/Panel.qml tests/ui/tst_shortcuts.qml tests/ui/tst_runs_flow.qml
git commit -m "feat(shortcuts): a bare e toggles Run detail between Output and Events"
```
<!-- task-pipeline: validated -->
