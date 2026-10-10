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
