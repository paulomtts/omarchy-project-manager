# 4.3 RunsScreen: Finished chips and Show older — design

Card: `47c1898d` (subtask of story `5e9efb63`, blocked by 4.2 `e41b2461`). Parent design:
`docs/superpowers/specs/2026-10-05-run-history-titles-design.md`, cited below as "P l.N".

## Purpose

The Runs screen exposes what 4.1 already put in the stores: a **Finished** status chip, under it
a finished-state row and an age row, and a **Show older** button per project that asks
`app.runHistory` for the next page of that project's older runs (P l.139-146, l.174-190). The
screen only reads store state and calls store methods; it owns no state.

## What already exists (not touched by this card)

- `app.runs` (`core/stores/RunStore.qml`):
  - `runFilter` accepts `"finished"`; `toggleRunFilter(id)` (l.~261).
  - `finishedState` (`""` | `done` | `escalated` | `cancelled`), `toggleFinishedState(id)`
    (l.~269): a known id other than the current selects it; the current one again or any other id
    (e.g. `"all"`) gives `""`.
  - `finishedAge` (`today` | `week` | `all`), `toggleFinishedAge(id)` (l.~278): `today` / `week`
    other than the current selects it; anything else, or the current again, gives `"all"`.
  - Both toggles emit `runFilterToggled()` (App puts the cursor home).
  - `runFilterCounts` (`{attention, live, parked, finished, all}`) over `listedRuns` (snapshot +
    loaded history) within the project filter.
  - `groups` / `filteredRuns` already apply the chip, `Runs.filterFinished` (state under Finished,
    age under Finished and All), the search and the project filter, history folded in.
  - `runsByProject` (`{root: runs[]}`): keys are registry roots **as the registry spells them**
    (a trailing `/` may remain); a run's `project.root` has it removed.
- `app.runHistory` (`core/stores/RunHistoryStore.qml`, composed in `core/stores/App.qml:183`):
  `historyByProject` (`{root: {runs, more, loading, error}}`, keyed exactly as `runsByProject`;
  a root has **no entry** until its first launched `showOlder`, and loses it when its pages are
  dropped — a changed query, the panel closing, the root leaving the snapshot);
  `showOlder(root)` pages **one root** (a no-op when inactive, for a root not in the snapshot,
  under a chip whose `Runs.historyStatuses` is empty, or with no cursor). The store is per root:
  P l.156-157's "one global keyset" and P l.188's "once, at the end of the list" are superseded by
  the store header (`RunHistoryStore.qml:7-29`) and `docs/architecture.md:95`; this card follows
  the card text: one button per project group.
- `Runs.historyStatuses(filter, finishedState)` (`core/domain/runs.js:760`): `[]` for `live`.
- `Runs.runState(run)`: `done`, `escalated`, `cancelled`, `parked`, … .
- `UI.ChipRow` (`ui/components/ChipRow.qml`): `model` `[{id, label, count?, tint}]`, `active`,
  `chipPrefix`, `chosen(id)`; a chip's objectName is `chipPrefix + id`.
- `UI.ActionButton`, `UI.ThemedText`, `UI.FilterableList` (`ui/components/FilterableList.qml`).
- The terminal cap: `TERMINAL_LIMIT = 10` lives only in `core/backend/common/am_runs.py:20`
  (snapshot keeps every non-terminal run plus the 10 newest terminal ones per project, terminal =
  `done, escalated, stopped, cancelled, canceled`, i.e. run states `done`, `escalated`,
  `cancelled`, `parked`).

## Inherited constraints

- Chips: Needs attention / Live / Parked / **Finished** / All (P l.139).
- Under Finished a second row **All finished / Done / Escalated / Cancelled** (P l.141-142).
- Under Finished and All an age row **Today / 7 days / All time**, default All time
  (P l.143-146).
- Show older appears when the snapshot listed `TERMINAL_LIMIT` terminal runs or the last page
  said `more`; reads `Loading older runs…` while a page is in flight; the error sentence in
  `urgent` on failure; it is a button, not a cursor row (P l.188-190); it is gone when exhausted
  (P l.224-225); on a failed page loaded rows stay (P l.200).
- `am` missing: Runs' missing state; no history (P l.203).
- `docs/architecture.md:168`: screens receive `app` / `navigator`, never import `core/stores`;
  shared components are reused, not copied (`tests/architecture/test_layers.py`); glyphs only from
  `ui/components/runGlyphs.js` (`tests/architecture/test_icon_glyphs.py`) — this card adds no
  glyph (`…` in `Loading older runs…` is U+2026 text, as in `Search runs…`).
- Docstrings and comments state the contract only, no narrative.
- Verification: `bash tests/run.sh` green.

## Behavior

### B1. Status chips

1. The status chip row (`runChips`) reads, in order: `Needs attention`, `Live`, `Parked`,
   `Finished`, `All` (ids `attention`, `live`, `parked`, `finished`, `all`). Every chip but All
   carries a count.
2. The counts come from `app.runs.runFilterCounts` (so loaded history runs count, and
   `Finished` shows `counts.finished`, e.g. `Finished 9`). The screen no longer derives counts
   from `app.runs.runs` itself.
3. `chipLabel("finished")` is `Finished`, so the filtered empty line reads `No Finished runs.`
4. Clicking a chip still calls `app.runs.toggleRunFilter(id)`; active chip is `runFilter`, `""`
   showing as `all`.

### B2. Finished-state row

1. A `UI.ChipRow`, objectName `runStateChips`, chip prefix `runStateChip`, chips
   `all` → `All finished`, `done` → `Done`, `escalated` → `Escalated`, `cancelled` →
   `Cancelled`; no counts; tint `theme.dim`.
2. Visible only when `app.runs.runFilter === "finished"` and am is not missing.
3. Active chip: `all` when `app.runs.finishedState` is `""`, else `finishedState`.
4. Clicking a chip calls `app.runs.toggleFinishedState(id)` with the chip id unchanged (`all`
   becomes `""` in the store).

### B3. Age row

1. A `UI.ChipRow`, objectName `runAgeChips`, chip prefix `runAgeChip`, chips `today` →
   `Today`, `week` → `7 days`, `all` → `All time`; no counts; tint `theme.dim`.
2. Visible only when `app.runs.runFilter` is `"finished"` or `""` (All) and am is not missing;
   hidden under Needs attention, Live and Parked.
3. Active chip: `app.runs.finishedAge` (`all` when it is anything other than `today` / `week`).
4. Clicking a chip calls `app.runs.toggleFinishedAge(id)` with the chip id unchanged.

### B4. Placement of the two rows

Both rows sit directly **under the status chips and above the status line and the list**, state
row first (P l.176-178). `UI.FilterableList` gains one optional slot for this, so no chip-row
pattern is copied into the screen:

- `property Component chipsFooter: null` — when non-null it is instantiated once, directly below
  the chip row and above the status line, with the chip row's visibility rule (shown only while
  not `loading` and `error` is `""`). When null nothing is created and the list lays out exactly
  as today (Issues, Memories, Documents, NewMilestoneDialog unchanged).

The Runs screen passes a component holding the two rows (B2, B3). Their own visibility rules
still apply inside it; when both are hidden the slot takes no height and adds no `spacing` gap
(the slot's Loader is `visible` only while the chip row's rule holds and its item's height is
above 0, since a Column spaces every visible child, even a zero-height one).

### B5. Show older button

One button per project, after that project's last run row:

1. **Where.** Grouped (no project filter): after each group's last run row, before the next
   header, for every group whose root is not `""`. Flat (a project filter): one, after the last
   run row, for the filtered project — also when no run passes the chips (the list is then the
   `No Finished runs.`-style line followed by the button). The error-only headers (a failed root
   with no runs) get none.
2. **Which root.** The group's root is matched to an own key of `app.runs.runsByProject` by
   `rootKey` (trailing `/` ignored); the button belongs to that key, and that exact key is what
   is passed to `showOlder` and read in `historyByProject`. No matching key: no button.
3. **When shown.** Never while am is missing, never when `app.runHistory` is null/absent, and
   never when `Runs.historyStatuses(app.runs.runFilter, app.runs.finishedState)` is empty (Live).
   Otherwise, for the key `K`:
   - `historyByProject` has an own entry for `K`: shown iff the entry's `loading` is `true`, its
     `error` is a non-empty string, or its `more` is `true`. A page that came back with
     `more: false` and no error hides it (exhausted).
   - No entry: shown iff `runsByProject[K]` holds at least `TERMINAL_LIMIT` (10) runs whose
     `Runs.runState` is `done`, `escalated`, `cancelled` or `parked`. Nine such runs: hidden.
   The cap is a named readonly property on the screen (`terminalLimit: 10`) with a comment
   tying it to the snapshot's per-project cap.
4. **Text.** `Loading older runs…` while the entry's `loading` is `true`, else `Show older`.
5. **Click.** Calls `app.runHistory.showOlder(K)` once. While loading the button is disabled
   (`enabled: false`) and a click calls nothing.
6. **Error.** When the entry's `error` is a non-empty string, a caption under the button shows
   that sentence verbatim in `theme.urgent`, wrapped; the button reads `Show older` and stays
   clickable (retry). The loaded history rows stay listed (they are the store's).
7. **Not a cursor row.** The button and its error caption are not `ListRow`s, take no index, and
   never shift a run row's index: `runRow<i>` is still the run at `filteredRuns[i]`; the cursor,
   hover, `openRun` and `p` / `r` / `c` act only on run rows.
8. **Names.** The k-th Show older entry in list order (from 0) has objectName
   `runsShowOlder<k>`, its caption `runsShowOlderError<k>`.

### B6. Entries

`entriesOf` stays a pure function of explicit arguments; it gains the snapshot map
(`runsByProject`), the history map (`historyByProject`) and the history status list (or an
equivalent boolean), and emits a new scalar entry `{ kind: "showOlder", k, root }` (scalars only:
the Repeater converts nested values) at the positions of B5.1 when B5.3 holds. The button's text,
enabled state and error caption are read live from `app.runHistory.historyByProject[root]` by the
delegate. Run entries' `i` values are unchanged by these entries. `RunEntry` maps `showOlder` to
the new delegate; unknown kinds still render nothing.

### B7. Header comment and docs

- `RunsScreen.qml`'s header comment names the Finished chip, the two rows and Show older, and
  that the screen reads `app.runHistory` and asks it for older pages (contract only).
- `docs/architecture.md:168` (the Runs screen paragraph): the chips become Needs attention /
  Live / Parked / Finished / All with `runFilterCounts`; the state and age rows and their
  visibility; Show older per project (when, text, error, not a cursor row, `showOlder(root)`);
  the run screens' read list adds `app.runHistory` for `RunsScreen`. FilterableList's line
  (l.~133) may name the optional `chipsFooter`. `tests/architecture/test_run_store_docs.py`
  must stay green (name no member a store does not own).

## Errors and edge cases

| case | behaviour |
|---|---|
| am missing | no chip rows of any kind, no Show older; the list's missing line only |
| `app.runHistory` null/absent (test harnesses) | no Show older, nothing throws |
| Live chip | no Show older (no statuses to page) |
| registry root with trailing `/` | button found by `rootKey`, `showOlder` gets the registry spelling |
| page in flight | `Loading older runs…`, disabled |
| page failed | `Show older`, enabled, error sentence in urgent beneath; loaded rows stay |
| page with `more: false` | button gone for that project |
| filter/age change drops pages | entry gone → back to the snapshot rule (10 terminal runs) |
| a group with exactly 9 terminal snapshot runs and no entry | no button |

## Tests

All QML tests run through `bash tests/run.sh` (qmltestrunner, offscreen).

### `tests/ui/components/tst_filterable_list.qml` — component tier (the slot is a shared component's contract, tested where the component is)

1. `chipsFooter` null: nothing extra is created; existing layout tests unchanged.
2. `chipsFooter` set: its item is created once and sits below the chip row and above the status
   line (y order).
3. `chipsFooter` is hidden while `loading` and while `error` is non-empty, like the chip row.

### `tests/ui/screens/tst_runs_screen.qml` — screen tier (stub stores isolate the screen's reading and calling contract)

Harness changes: the `runsC` stub gains `finishedState`, `finishedAge`, `runsByProject`,
`runFilterCounts` and recording `toggleFinishedState` / `toggleFinishedAge` (mirroring the real
store's semantics); a `historyC` stub with `historyByProject` and a recording `showOlder(root)`;
`appC` gains `runHistory`.

1. The status chips read `Needs attention n`, `Live n`, `Parked n`, `Finished n`, `All` in that
   order; counts come from `runFilterCounts` (a stub value differing from the snapshot proves
   the source).
2. `No Finished runs.` under Finished with no match.
3. Chip rows visibility per filter: state row only under Finished; age row under Finished and
   All; neither under Needs attention, Live, Parked; neither while am is missing.
4. State row: labels; active follows `finishedState` (`""` → `All finished`); clicking `Done`
   records `toggleFinishedState("done")`, clicking `All finished` records `"all"`.
5. Age row: labels `Today`, `7 days`, `All time`; active follows `finishedAge`; clicking
   `7 days` records `toggleFinishedAge("week")`.
6. The rows sit below `runChips` and above the first list entry.
7. Show older visible: a root with 10 terminal snapshot runs and no entry → `runsShowOlder0`
   reads `Show older`; 9 terminal runs (plus live ones) → no button.
8. Show older from history: entry `more: true` → shown; `more: false`, no error, not loading →
   hidden even with 10 terminal snapshot runs.
9. Grouped: two projects, each eligible → `runsShowOlder0` after group 0's last run and before
   group 1's header, `runsShowOlder1` after group 1's last run (y order); an ineligible project
   gets none.
10. Flat under a project filter: one button after the last row, for the filtered root; also
    shown when the chip leaves no row.
11. Loading: entry `loading: true` → text `Loading older runs…`, `enabled` false, a click records
    no `showOlder`.
12. Error: entry `error: "am failed"` → `runsShowOlderError0` reads it in `theme.urgent`; button
    reads `Show older` and is enabled.
13. Click calls `showOlder` with the registry key spelling (a root registered as `/home/u/a/`
    records `/home/u/a/`).
14. Live chip → no button; am missing → no button; `runHistory` null → no button, no warnings
    thrown.
15. The cursor skips it: with a button between two groups, `runRow<i>` objectNames still match
    `filteredRuns` positions; setting `cursorIndex` to the last run gives exactly that row the
    cursor; `entriesOf` returns the same `i` sequence with and without showOlder entries.
16. `entriesOf` pure cases: showOlder entry positions (grouped, flat, error-only header gets
    none, `""` root gets none).

### `tests/ui/tst_runs_flow.qml` — integration tier (real `App` stores; proves the wiring to the real `RunStore` / `RunHistoryStore`)

17. Clicking `Finished` then `Done` on the real screen sets `app.runs.runFilter` `finished` and
    `app.runs.finishedState` `done`; clicking `7 days` sets `finishedAge` `week`.
18. Existing flow and `tst_runs_real_data.qml` cases stay green with `app.runHistory` present.

### Architecture tier (`tests/architecture`, pytest)

19. `test_layers.py`, `test_icon_glyphs.py` and `test_run_store_docs.py` pass unchanged.

## Out of scope

- Any store or domain change (`RunStore`, `RunHistoryStore`, `runs.js`, App wiring): 4.1 and
  earlier cards. If a store contract is found wrong, it is reported, not changed here.
- Backend (`runs-history.py`, `am_runs.py`) and any shared JS constant for `TERMINAL_LIMIT`.
- Run detail of history runs, titles, Refresh titles (4.2 and earlier).
- A Show older for a project whose runs the chips hide entirely in the grouped view (its group is
  absent); the project filter's flat view offers it.
- Keyboard access to Show older; persistence of the chips.

---

# 4.3 RunsScreen: Finished chips and Show older — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Runs screen shows a Finished status chip with counts from `app.runs.runFilterCounts`, a finished-state row and an age row under the status chips, and a per-project Show older button that asks `app.runHistory.showOlder(root)` for older runs.

**Architecture:** `ui/components/FilterableList.qml` gains an optional `chipsFooter` slot (a `Loader` between the chip row and the status line) that the Runs screen fills with two `UI.ChipRow`s. `RunsScreen.entriesOf` stays pure and gains three arguments (the snapshot map, the history map, a may-show flag); it emits scalar `{ kind: "showOlder", k, root }` entries that a new non-row delegate (`OlderRuns`) renders, reading its text, enabled state and error live from `app.runHistory.historyByProject[root]`. No store or domain file changes.

**Tech Stack:** QML (Qt 6, Quickshell stubs under `tests/stubs`), JS domain library `core/domain/runs.js`, QtTest via `qmltestrunner`, pytest architecture tests, all driven by `bash tests/run.sh`.

**Spec:** `docs/superpowers/specs/4-3-runsscreen-finished-47c1898d.md` (reproduced above).

## Global Constraints

- Screens receive `app` / `navigator` and never import `core/stores` (`docs/architecture.md:168`, `tests/architecture/test_layers.py`).
- Shared components are reused, not copied: the two new rows are `UI.ChipRow`, the button is `UI.ActionButton`, the caption is `UI.ThemedText`; no `bordered: true`, `radius: height / 2`, `font.family:`, `CursorSurface {` or `Qt.rgba(0, 0, 0, 0.55)` in `RunsScreen.qml` (`tests/architecture/test_layers.py` GUARDS).
- Glyphs only from `ui/components/runGlyphs.js`; this card adds none. `…` in `Loading older runs…` is the text character U+2026.
- Docstrings and comments state the contract only, no narrative.
- Chip ids / labels exactly: status `attention` Needs attention, `live` Live, `parked` Parked, `finished` Finished, `all` All; state row `all` All finished, `done` Done, `escalated` Escalated, `cancelled` Cancelled; age row `today` Today, `week` 7 days, `all` All time.
- ObjectNames exactly: `runChips`/`runChip<id>`, `runStateChips`/`runStateChip<id>`, `runAgeChips`/`runAgeChip<id>`, `runsShowOlder<k>`, `runsShowOlderError<k>`.
- Button text exactly `Show older` / `Loading older runs…`.
- `terminalLimit: 10` is a named readonly property on the screen, its comment tying it to `TERMINAL_LIMIT` in `core/backend/common/am_runs.py`.
- No change to `RunStore`, `RunHistoryStore`, `runs.js`, `App.qml` or the backend.
- Verification: `bash tests/run.sh` green (pytest + every QML test, no `TypeError` / `ReferenceError` / `non-existent` / `Unable to assign` lines).

### Deviation from spec B4 (read before Task 1)

B4 asks for the slot's Loader to be `visible` only while "its item's height is above 0". That rule latches: an invisible Loader makes its item's children effectively invisible, a `Column`/`Flow` then lays them out at height 0, so the Loader can never become visible again. This was reproduced with `qmltestrunner` on this machine (a Loader bound to `item.height > 0` stayed hidden after its child became visible). The plan therefore adds one bool beside the slot, `chipsFooterShown` (default `true`): the Loader is `visible` while `chipsFooter !== null && chipsFooterShown && !loading && error === ""`. The Runs screen binds `chipsFooterShown` to exactly the union of its two rows' own rules (`!amMissing && (runFilter === "finished" || runFilter === "")`), so the slot takes no height and adds no spacing gap whenever both rows are hidden — the behaviour B4 asks for. Every other FilterableList caller (Issues, Memories, Documents, NewMilestoneDialog) sets neither property and lays out exactly as today.

## Review Focus

1. A failed page whose entry also says `more: false` must still offer the button (retry) with the error under it — Task 5's error test uses `more: false`.
2. Garbage maps — `historyByProject` null, an entry that is `null` / a string / an object with non-boolean `loading`/`more` and a non-string `error`; `runsByProject` null, a list that is not an array, runs that are not objects — must fall back to the snapshot rule or hide the button, and never throw — Task 4 `test_garbage_history_and_snapshot_maps_fall_back_and_do_not_throw`.
3. A root that `runsByProject` holds twice (`/home/u/a` and `/home/u/a/`) must give that project exactly one button, for the first own key in key order — Task 4 `test_show_older_passes_the_registry_spelling_and_a_doubled_root_gets_one_button`.
4. Changing the chip to Live and back to All (no new snapshot) must hide and then bring back the button — Task 4 `test_show_older_is_hidden_under_live_with_am_missing_and_without_a_run_history`.
5. A page that settles (`loading: true` → `more: true` → `more: false`) must update the same button's text, enabled state and visibility live — Task 5 `test_a_page_in_flight_reads_loading_and_takes_no_click`.

## File map

- Modify `ui/components/FilterableList.qml` — the `chipsFooter` / `chipsFooterShown` slot (Task 1).
- Modify `tests/ui/components/tst_filterable_list.qml` — slot tests (Task 1).
- Modify `ui/screens/RunsScreen.qml` — Finished chip and counts (Task 2), state and age rows (Task 3), Show older entries and delegate (Tasks 4–5), header comment (Task 6).
- Modify `tests/ui/screens/tst_runs_screen.qml` — harness stubs (Task 2), tests for Tasks 2–5.
- Modify `tests/ui/tst_runs_flow.qml` — real-store wiring tests (Tasks 3 and 5).
- Modify `docs/architecture.md` — Runs paragraph and FilterableList line (Task 6).

## How to run one QML test fast

`bash tests/run.sh <filter>` runs the whole pytest suite (~2 min) before the filtered QML files. While iterating, run a QML file (or one function) directly from the worktree root:

```bash
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/screens/tst_runs_screen.qml RunsScreen::test_name 2>&1 | grep -E "^(PASS|FAIL|Totals)|^   (Loc|Actual|Expected)|TypeError|ReferenceError"
```

Omit `RunsScreen::test_name` to run the whole file. TestCase names: `FilterableList`, `RunsScreen`, `RunsFlow`. Every task still ends with the full `bash tests/run.sh`.

---

### Task 1: FilterableList `chipsFooter` slot

**Files:**
- Modify: `ui/components/FilterableList.qml` (whole file, 63 lines)
- Test: `tests/ui/components/tst_filterable_list.qml`

**Interfaces:**
- Consumes: nothing.
- Produces: on `FilterableList`: `property Component chipsFooter: null`, `property bool chipsFooterShown: true`; the slot's `Loader` has objectName `chipsObjectName + "Footer"` (the Runs screen's is `runChipsFooter`).

- [ ] **Step 1: Write the failing tests**

In `tests/ui/components/tst_filterable_list.qml`, after the line `SignalSpy { id: chipSpy; signalName: "chipToggled" }` add:

```qml
  // How many footer items the slot has made.
  property int footersMade: 0

  Component {
    id: footerC
    Rectangle {
      objectName: "myFooter"
      width: 10
      height: 20
      Component.onCompleted: tc.footersMade += 1
    }
  }

  // An item's top edge in the list's coordinates.
  function topIn(list, name) { return H.find(list, name).mapToItem(list, 0, 0).y }
```

In `make()`, after `chipSpy.clear()` add `tc.footersMade = 0`.

At the end of the TestCase (before the final `}`) add:

```qml
  function test_without_a_footer_nothing_is_added_and_the_layout_is_unchanged() {
    var list = make()
    list.chips = chips
    list.model = rows
    wait(20)
    var slot = H.find(list, "myChipsFooter")
    verify(slot, "the slot exists")
    compare(slot.item, null, "nothing is created")
    compare(slot.visible, false)
    compare(tc.footersMade, 0)
    compare(topIn(list, "myRow0"), topIn(list, "myChips") + H.find(list, "myChips").height + list.spacing,
            "the first row follows the chips with one gap")
  }

  function test_a_footer_is_made_once_under_the_chips_and_above_the_status_line() {
    var list = make()
    list.chipsFooter = footerC
    list.chips = chips
    list.empty = true
    wait(20)
    compare(tc.footersMade, 1)
    var footer = H.find(list, "myFooter")
    verify(footer)
    compare(footer.visible, true)
    compare(footer.width, 360, "the slot gives the footer the list's width")
    verify(topIn(list, "myChips") < topIn(list, "myFooter"), "under the chips")
    compare(topIn(list, "myStatus"), topIn(list, "myFooter") + 20 + list.spacing, "the status line follows it")
    list.chips = [{ id: "c", label: "Gamma" }]
    list.empty = false
    list.model = rows
    wait(20)
    compare(tc.footersMade, 1, "never made again")
  }

  function test_the_footer_hides_while_loading_or_failed_like_the_chips() {
    var list = make()
    list.chipsFooter = footerC
    list.chips = chips
    wait(20)
    compare(H.find(list, "myFooter").visible, true)
    list.loading = true
    compare(H.find(list, "myFooter").visible, false)
    list.loading = false
    list.error = "boom"
    compare(H.find(list, "myFooter").visible, false)
    list.error = ""
    compare(H.find(list, "myFooter").visible, true)
  }

  function test_a_footer_the_owner_hides_takes_no_height_and_no_gap() {
    var list = make()
    list.chipsFooter = footerC
    list.chips = chips
    list.empty = true
    list.chipsFooterShown = false
    wait(20)
    compare(H.find(list, "myFooter").visible, false)
    compare(topIn(list, "myStatus"), topIn(list, "myChips") + H.find(list, "myChips").height + list.spacing,
            "the status line follows the chips with one gap")
    list.chipsFooterShown = true
    wait(20)
    compare(H.find(list, "myFooter").visible, true, "shown again")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/components/tst_filterable_list.qml 2>&1 | grep -E "^(PASS|FAIL|Totals)|^   (Loc|Actual|Expected)"`
Expected: the four new tests FAIL (`myChipsFooter` not found / `chipsFooter` is a non-existent property); the nine existing tests PASS.

- [ ] **Step 3: Implement the slot**

In `ui/components/FilterableList.qml` replace the header comment

```qml
// The shape both list sections share: a row of filter chips, one status line
// instead of the rows when there is something to say, and the rows themselves.
// The caller supplies the row delegate and every piece of wording, so nothing
// domain-specific lives here.
```

with

```qml
// The shape both list sections share: a row of filter chips, optionally an
// item of the caller's under it, one status line instead of the rows when
// there is something to say, and the rows themselves. The caller supplies the
// row delegate and every piece of wording, so nothing domain-specific lives
// here.
```

Replace

```qml
  property Component rowDelegate: null
```

with

```qml
  property Component rowDelegate: null
  // Made once, directly under the chip row and above the status line, when
  // not null; shown while chipsFooterShown is true and the chip row's rule
  // holds (not loading, no error). Hidden, it takes no height and no gap.
  property Component chipsFooter: null
  property bool chipsFooterShown: true
```

Between the `ChipRow { … }` block and the `ListStatus {` block insert:

```qml
  Loader {
    objectName: list.chipsObjectName + "Footer"
    width: parent.width
    sourceComponent: list.chipsFooter
    visible: list.chipsFooter !== null && list.chipsFooterShown && !list.loading && list.error === ""
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/components/tst_filterable_list.qml 2>&1 | grep -E "^(FAIL|Totals)"`
Expected: `Totals: 13 passed, 0 failed` (11 tests + init/cleanup).

- [ ] **Step 5: Run the full suite**

Run: `bash tests/run.sh`
Expected: pytest all passed; every QML file `0 failed`; no TypeError/ReferenceError lines; exit status 0 (the Issues, Memories, Documents and NewMilestoneDialog lists are unchanged).

- [ ] **Step 6: Commit**

```bash
git add ui/components/FilterableList.qml tests/ui/components/tst_filterable_list.qml
git commit -m "feat(ui): FilterableList's optional chipsFooter sits under the chip row and above the status line"
```

---

### Task 2: Finished status chip, counts from `runFilterCounts`, and the test harness

**Files:**
- Modify: `ui/screens/RunsScreen.qml:47-48` (the `counts` property), `:70-73` (`chipLabel`), `:312-316` (the `chips:` binding)
- Test: `tests/ui/screens/tst_runs_screen.qml` (harness `runsC`, new `historyC`, `appC`, `make()`; chip tests)

**Interfaces:**
- Consumes: `app.runs.runFilterCounts` (`{attention, live, parked, finished, all}`), `app.runs.toggleRunFilter(id)`.
- Produces: `RunsScreen.chipLabel("finished") === "Finished"`; chip `runChipfinished`. Test harness (used by Tasks 3–5): `s.runs.countsOverride`, `s.runs.finishedState`, `s.runs.finishedAge`, `s.runs.finishedCalls` (strings `"state|<id>"` / `"age|<id>"`), `s.runs.runsByProject`, `s.history.historyByProject`, `s.history.showOlderCalls` (roots in call order), `s.app.runHistory`; test helpers `doneRuns(n, root, name, tag)`, `page(o)`, `shape(entries)`, `runIds(from, n)`.

- [ ] **Step 1: Extend the harness**

In `tests/ui/screens/tst_runs_screen.qml`, in the `runsC` component replace

```qml
      readonly property var groups: Runs.groupByProject(Runs.filterByProject(Runs.searchRuns(Runs.filterRuns(rs.runs, rs.runFilter), rs.searchQuery), rs.projectFilter))
      readonly property var filteredRuns: Runs.displayOrder(rs.groups)
      function toggleRunFilter(id) { rs.runFilter = id === "all" || id === rs.runFilter ? "" : id }
```

with

```qml
      // The Finished chip's state and age rows, as the real store holds them.
      property string finishedState: ""
      property string finishedAge: "all"
      // Each runsByProject key is a registry root as the registry spells it.
      property var runsByProject: ({})
      // When not null, the chip counts a test forces; else the real store's.
      property var countsOverride: null
      readonly property var runFilterCounts: rs.countsOverride !== null ? rs.countsOverride
        : Runs.runFilterCounts(Runs.filterByProject(rs.runs, rs.projectFilter))
      readonly property var groups: {
        var now = Date.now()
        var state = rs.runFilter === "finished" ? rs.finishedState : ""
        var age = rs.runFilter === "finished" || rs.runFilter === "" ? rs.finishedAge : "all"
        var kept = Runs.filterFinished(Runs.filterRuns(rs.runs, rs.runFilter), state, age, now, -new Date(now).getTimezoneOffset())
        return Runs.groupByProject(Runs.filterByProject(Runs.searchRuns(kept, rs.searchQuery), rs.projectFilter))
      }
      readonly property var filteredRuns: Runs.displayOrder(rs.groups)
      function toggleRunFilter(id) { rs.runFilter = id === "all" || id === rs.runFilter ? "" : id }
      // The real store's toggles; every call is recorded as "state|<id>" or
      // "age|<id>".
      property var finishedCalls: []
      function toggleFinishedState(id) {
        rs.finishedCalls = rs.finishedCalls.concat(["state|" + id])
        var known = id === "done" || id === "escalated" || id === "cancelled"
        rs.finishedState = known && id !== rs.finishedState ? id : ""
      }
      function toggleFinishedAge(id) {
        rs.finishedCalls = rs.finishedCalls.concat(["age|" + id])
        var known = id === "today" || id === "week"
        rs.finishedAge = known && id !== rs.finishedAge ? id : "all"
      }
```

After the `titlesC` component block (it ends with `function refreshTitles() { ts.refreshCalls += 1 }` and two closing braces) add:

```qml
  // The run history store's surface: {root: {runs, more, loading, error}}
  // and showOlder(root), which only records its argument.
  Component {
    id: historyC
    QtObject {
      id: hs
      property var historyByProject: ({})
      property var showOlderCalls: []
      function showOlder(root) { hs.showOlderCalls = hs.showOlderCalls.concat([root]) }
    }
  }
```

In the `appC` component replace

```qml
      property var runTitles: null
```

with

```qml
      property var runTitles: null
      property var runHistory: null
```

In `make()` replace

```qml
    var titles = titlesC.createObject(host)
    var app = appC.createObject(host, { nav: nav, runs: runs, runControl: control, runTitles: titles })
```

with

```qml
    var titles = titlesC.createObject(host)
    var history = historyC.createObject(host)
    var app = appC.createObject(host, { nav: nav, runs: runs, runControl: control, runTitles: titles, runHistory: history })
```

and replace

```qml
    return { app: app, runs: runs, control: control, titles: titles, nav: nav, navi: navi, screen: screen }
```

with

```qml
    return { app: app, runs: runs, control: control, titles: titles, history: history, nav: nav, navi: navi, screen: screen }
```

After the `projectChipText` helper add:

```qml
  // `n` done runs of the project at `root` named `name`, ids
  // run-<tag>-done1000, run-<tag>-done1001, …
  function doneRuns(n, root, name, tag) {
    var out = []
    for (var i = 0; i < n; i++) out.push(tagged(run("run-" + tag + "-done" + (1000 + i), "done", null, {}), root, name))
    return out
  }

  // A history entry: no runs; `more`, `loading` and `error` from `o`, else
  // false, false and "".
  function page(o) {
    var p = o || {}
    return { runs: [], more: p.more === true, loading: p.loading === true, error: p.error || "" }
  }

  // An entries list as one string: h<g> a header, r<i> a run,
  // o<k>:<root> a Show older, e the filtered project's error.
  function shape(entries) {
    return entries.map(function(e) {
      return e.kind === "header" ? "h" + e.g : e.kind === "run" ? "r" + e.i
        : e.kind === "showOlder" ? "o" + e.k + ":" + e.root : "e"
    }).join(",")
  }

  // "r<from>,…,r<from + n - 1>".
  function runIds(from, n) {
    var out = []
    for (var i = 0; i < n; i++) out.push("r" + (from + i))
    return out.join(",")
  }
```

- [ ] **Step 2: Write the failing tests**

Replace the existing `test_the_chips_carry_the_counts` with:

```qml
  function test_the_chips_carry_the_counts() {
    var s = make(sample()); if (!s) return
    compare(H.find(s.screen, "runChipattention").text, "Needs attention 2")
    compare(H.find(s.screen, "runChiplive").text, "Live 1")
    compare(H.find(s.screen, "runChipparked").text, "Parked 1")
    compare(H.find(s.screen, "runChipfinished").text, "Finished 3")
    compare(H.find(s.screen, "runChipall").text, "All")
    compare(H.find(s.screen, "runChipall").active, true, "All is active with no filter")
  }

  function test_the_status_chips_are_in_order_and_count_from_run_filter_counts() {
    var s = make(sample()); if (!s) return
    var model = H.find(s.screen, "runChips").model
    compare(model.map(function(c) { return c.id }).join(","), "attention,live,parked,finished,all")
    s.runs.countsOverride = { attention: 7, live: 8, parked: 9, finished: 11, all: 50 }
    compare(H.find(s.screen, "runChipattention").text, "Needs attention 7")
    compare(H.find(s.screen, "runChiplive").text, "Live 8")
    compare(H.find(s.screen, "runChipparked").text, "Parked 9")
    compare(H.find(s.screen, "runChipfinished").text, "Finished 11", "the store's count, not the snapshot's 3")
    compare(H.find(s.screen, "runChipall").text, "All")
  }

  function test_the_finished_chip_filters_and_names_its_empty_list() {
    var s = make([run("run-x-live0001", "started", true, {}), run("run-x-dead0002", "started", false, {})]); if (!s) return
    tap(H.find(s.screen, "runChipfinished"))
    compare(s.runs.runFilter, "finished")
    compare(H.find(s.screen, "runChipfinished").active, true)
    compare(H.find(s.screen, "runRow0"), null)
    compare(H.find(s.screen, "runsMessage").text, "No Finished runs.")
    compare(s.screen.chipLabel("finished"), "Finished")
  }
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/screens/tst_runs_screen.qml 2>&1 | grep -E "^(FAIL|Totals)|^   (Loc|Actual|Expected)|TypeError"`
Expected: the three tests above FAIL (`runChipfinished` not found → TypeError reading `.text`; the counts read `Needs attention 2`, not 7); every other test PASSES (the harness change keeps the derived counts and groups).

- [ ] **Step 4: Implement**

In `ui/screens/RunsScreen.qml` delete

```qml
  // The status chips' counts: the project filter's runs, whatever the search.
  readonly property var counts: Runs.runFilterCounts(Runs.filterByProject(screen.app.runs.runs, screen.app.runs.projectFilter))
```

Replace

```qml
    return id === "attention" ? "Needs attention" : id === "live" ? "Live" : id === "parked" ? "Parked" : "All"
```

with

```qml
    return id === "attention" ? "Needs attention" : id === "live" ? "Live" : id === "parked" ? "Parked"
      : id === "finished" ? "Finished" : "All"
```

Replace

```qml
    chips: ["attention", "live", "parked", "all"].map(function(id) {
      var chip = { id: id, label: screen.chipLabel(id), tint: screen.theme.dim }
      if (id !== "all") chip.count = screen.counts[id]
      return chip
    })
```

with

```qml
    // Counts from the store: listed runs (snapshot and loaded history) in the
    // project filter, whatever the chip, the finished rows or the search.
    chips: ["attention", "live", "parked", "finished", "all"].map(function(id) {
      var chip = { id: id, label: screen.chipLabel(id), tint: screen.theme.dim }
      if (id !== "all") chip.count = screen.app.runs.runFilterCounts[id]
      return chip
    })
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/screens/tst_runs_screen.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError"`
Expected: `0 failed`, no error lines.

- [ ] **Step 6: Run the full suite**

Run: `bash tests/run.sh`
Expected: exit status 0; `tst_runs_flow.qml`, `tst_runs_real_data.qml` and `tst_panel_toolbar.qml` green (the real store has `runFilterCounts`).

- [ ] **Step 7: Commit**

```bash
git add ui/screens/RunsScreen.qml tests/ui/screens/tst_runs_screen.qml
git commit -m "feat(runs): a Finished status chip, every chip counted from the store's runFilterCounts"
```

---

### Task 3: The finished-state row and the age row

**Files:**
- Modify: `ui/screens/RunsScreen.qml` (new properties beside `projectChips`; the `UI.FilterableList` block)
- Test: `tests/ui/screens/tst_runs_screen.qml`, `tests/ui/tst_runs_flow.qml`

**Interfaces:**
- Consumes: Task 1's `chipsFooter` / `chipsFooterShown`; `app.runs.finishedState`, `app.runs.finishedAge`, `app.runs.toggleFinishedState(id)`, `app.runs.toggleFinishedAge(id)`; Task 2's harness (`finishedCalls`).
- Produces: `RunsScreen.finishedStateChips`, `RunsScreen.finishedAgeChips` (ChipRow models), `RunsScreen.activeAgeChipOf(age)`; ChipRows `runStateChips` / `runAgeChips` inside the Loader `runChipsFooter`.

- [ ] **Step 1: Write the failing screen tests**

In `tests/ui/screens/tst_runs_screen.qml`, after `test_the_finished_chip_filters_and_names_its_empty_list` add:

```qml
  // ---- the Finished chip's rows (4.3)

  function test_the_state_row_shows_under_finished_and_the_age_row_under_finished_and_all() {
    var s = make(sample()); if (!s) return
    var cases = [["", false, true], ["attention", false, false], ["live", false, false],
                 ["parked", false, false], ["finished", true, true]]
    for (var c = 0; c < cases.length; c++) {
      s.runs.runFilter = cases[c][0]
      wait(20)
      compare(shown(s, "runStateChips"), cases[c][1], "the state row under '" + cases[c][0] + "'")
      compare(shown(s, "runAgeChips"), cases[c][2], "the age row under '" + cases[c][0] + "'")
      compare(H.find(s.screen, "runChipsFooter").visible, cases[c][2], "the slot under '" + cases[c][0] + "'")
    }
    s.runs.amStatus = "missing"
    wait(20)
    compare(shown(s, "runStateChips"), false, "am missing")
    compare(shown(s, "runAgeChips"), false, "am missing")
  }

  function test_the_state_row_reads_and_toggles_the_finished_state() {
    var s = make(sample()); if (!s) return
    s.runs.toggleRunFilter("finished")
    wait(20)
    var ids = ["all", "done", "escalated", "cancelled"]
    var labels = ["All finished", "Done", "Escalated", "Cancelled"]
    for (var i = 0; i < ids.length; i++) compare(H.find(s.screen, "runStateChip" + ids[i]).text, labels[i])
    compare(H.find(s.screen, "runStateChips").model.length, 4)
    compare(H.find(s.screen, "runStateChipall").active, true, "\"\" is All finished")
    s.runs.finishedState = "escalated"
    compare(H.find(s.screen, "runStateChipescalated").active, true)
    compare(H.find(s.screen, "runStateChipall").active, false)
    s.runs.finishedState = ""
    tap(H.find(s.screen, "runStateChipdone"))
    compare(s.runs.finishedCalls.join(","), "state|done")
    compare(s.runs.finishedState, "done")
    compare(H.find(s.screen, "runStateChipdone").active, true)
    tap(H.find(s.screen, "runStateChipall"))
    compare(s.runs.finishedCalls.join(","), "state|done,state|all", "the chip id goes to the store unchanged")
    compare(s.runs.finishedState, "")
  }

  function test_the_age_row_reads_and_toggles_the_finished_age() {
    var s = make(sample()); if (!s) return
    var ids = ["today", "week", "all"]
    var labels = ["Today", "7 days", "All time"]
    for (var i = 0; i < ids.length; i++) compare(H.find(s.screen, "runAgeChip" + ids[i]).text, labels[i])
    compare(H.find(s.screen, "runAgeChips").model.length, 3)
    compare(H.find(s.screen, "runAgeChipall").active, true, "All time by default")
    s.runs.finishedAge = "today"
    compare(H.find(s.screen, "runAgeChiptoday").active, true)
    compare(H.find(s.screen, "runAgeChipall").active, false)
    s.runs.finishedAge = "bogus"
    compare(H.find(s.screen, "runAgeChipall").active, true, "anything else is All time")
    s.runs.finishedAge = "all"
    tap(H.find(s.screen, "runAgeChipweek"))
    compare(s.runs.finishedCalls.join(","), "age|week")
    compare(s.runs.finishedAge, "week")
    compare(H.find(s.screen, "runAgeChipweek").active, true)
  }

  function test_the_finished_rows_sit_under_the_status_chips_and_above_the_list() {
    var s = make([run("run-x-live0001", "started", true, {})]); if (!s) return
    s.runs.toggleRunFilter("finished")
    wait(20)
    verify(topOf(s, "runChips") < topOf(s, "runStateChips"), "under the status chips")
    verify(topOf(s, "runStateChips") < topOf(s, "runAgeChips"), "the state row first")
    verify(topOf(s, "runAgeChips") < topOf(s, "runsMessage"), "above the status line")
    s.runs.toggleRunFilter("all")
    wait(20)
    verify(topOf(s, "runAgeChips") < topOf(s, "runRow0"), "above the first row")
  }
```

- [ ] **Step 2: Write the failing flow test**

In `tests/ui/tst_runs_flow.qml`, after `test_chip_search_cursor_enter_and_escape` add:

```qml
  function test_the_finished_chip_and_its_rows_set_the_real_store() {
    var p = make(); if (!p) return
    p.shortcuts.handleGlobalKey({ modifiers: Qt.ControlModifier, key: Qt.Key_6 })
    wait(50)
    H.find(p, "runChipfinished").clicked()
    compare(p.app.runs.runFilter, "finished")
    wait(20)
    compare(H.find(p, "runStateChips").visible, true)
    H.find(p, "runStateChipdone").clicked()
    compare(p.app.runs.finishedState, "done")
    compare(H.find(p, "runStateChipdone").active, true)
    H.find(p, "runAgeChipweek").clicked()
    compare(p.app.runs.finishedAge, "week")
    compare(H.find(p, "runAgeChipweek").active, true)
  }
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/screens/tst_runs_screen.qml 2>&1 | grep -E "^(FAIL|Totals)"`
Expected: the four new tests FAIL (`runStateChips` / `runAgeChips` / `runChipsFooter` not found).

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/tst_runs_flow.qml RunsFlow::test_the_finished_chip_and_its_rows_set_the_real_store 2>&1 | grep -E "^(FAIL|Totals)|TypeError"`
Expected: FAIL (TypeError: `runStateChips` is null).

- [ ] **Step 4: Implement**

In `ui/screens/RunsScreen.qml`, after

```qml
  // The project chip row's model (projectChipsOf).
  readonly property var projectChips: screen.projectChipsOf(screen.allGroups, screen.openRoot)
```

add

```qml
  // The Finished chip's state row and age row, scalar values only.
  readonly property var finishedStateChips: [
    { id: "all", label: "All finished", tint: screen.theme.dim },
    { id: "done", label: "Done", tint: screen.theme.dim },
    { id: "escalated", label: "Escalated", tint: screen.theme.dim },
    { id: "cancelled", label: "Cancelled", tint: screen.theme.dim }
  ]
  readonly property var finishedAgeChips: [
    { id: "today", label: "Today", tint: screen.theme.dim },
    { id: "week", label: "7 days", tint: screen.theme.dim },
    { id: "all", label: "All time", tint: screen.theme.dim }
  ]
  // The state row shows under Finished, the age row under Finished and All;
  // neither while am is missing.
  readonly property bool stateRowShown: !screen.amMissing && screen.app.runs.runFilter === "finished"
  readonly property bool ageRowShown: !screen.amMissing
    && (screen.app.runs.runFilter === "finished" || screen.app.runs.runFilter === "")
```

After the `chooseProject(id)` function add

```qml
  // The age chip `age` (the store's finishedAge) makes active: "today" and
  // "week" themselves, "all" for anything else.
  function activeAgeChipOf(age) {
    return age === "today" || age === "week" ? age : "all"
  }
```

In the `UI.FilterableList { … }` block, after the line `onChipToggled: function(id) { screen.app.runs.toggleRunFilter(id) }` add

```qml

    // Under the status chips: the state row, then the age row; the store
    // toggles each with the chip's id.
    chipsFooterShown: screen.ageRowShown
    chipsFooter: Component {
      Column {
        spacing: Style.space(6)

        UI.ChipRow {
          objectName: "runStateChips"
          width: parent.width
          theme: screen.theme
          chipPrefix: "runStateChip"
          visible: screen.stateRowShown
          model: screen.finishedStateChips
          active: screen.app.runs.finishedState === "" ? "all" : screen.app.runs.finishedState
          onChosen: function(id) { screen.app.runs.toggleFinishedState(id) }
        }

        UI.ChipRow {
          objectName: "runAgeChips"
          width: parent.width
          theme: screen.theme
          chipPrefix: "runAgeChip"
          visible: screen.ageRowShown
          model: screen.finishedAgeChips
          active: screen.activeAgeChipOf(screen.app.runs.finishedAge)
          onChosen: function(id) { screen.app.runs.toggleFinishedAge(id) }
        }
      }
    }
```

(`ageRowShown` is the union of both rows' rules, since the state row's rule implies the age row's; see "Deviation from spec B4".)

- [ ] **Step 5: Run the tests to verify they pass**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/screens/tst_runs_screen.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError"`
Expected: `0 failed`.

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/tst_runs_flow.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError"`
Expected: `0 failed`.

- [ ] **Step 6: Run the full suite**

Run: `bash tests/run.sh`
Expected: exit status 0. If an existing click test in `tst_runs_screen.qml` now misses its target because the age row pushed it below the 700 px window, report it rather than editing the test's expectations.

- [ ] **Step 7: Commit**

```bash
git add ui/screens/RunsScreen.qml tests/ui/screens/tst_runs_screen.qml tests/ui/tst_runs_flow.qml
git commit -m "feat(runs): under Finished a state row, under Finished and All an age row, both toggled through the run store"
```

---

### Task 4: Show older entries, eligibility and the button

**Files:**
- Modify: `ui/screens/RunsScreen.qml` (properties near `entries`, `entriesOf` and its comment, new helpers, `RunEntry`, new `OlderRuns` component)
- Test: `tests/ui/screens/tst_runs_screen.qml`

**Interfaces:**
- Consumes: `app.runs.runsByProject` (`{registryRoot: runs[]}`), `app.runHistory.historyByProject` (`{key: {runs, more, loading, error}}`), `app.runHistory.showOlder(root)`, `Runs.historyStatuses(filter, finishedState)`, `Runs.runState(run)`, `Runs.hasKey(map, key)`; Task 2 harness helpers.
- Produces:
  - `readonly property int terminalLimit: 10`
  - `readonly property var runHistory` (the store or `null`)
  - `readonly property bool canShowOlder`
  - `function historyKeyOf(byProject, root) -> string` (own key matched by `rootKey`, `""` if none)
  - `function historyEntryOf(history, key) -> object|null`
  - `function terminalCountOf(list) -> int`
  - `function offersOlder(byProject, history, key) -> bool`
  - `function entriesOf(groups, runs, roots, errors, filter, status, byProject, history, older) -> [entry]`, new entry `{ kind: "showOlder", k, root }`
  - inline `component OlderRuns: Column` with `property int k`, `property string root`; button `runsShowOlder<k>` (Task 5 extends it).

- [ ] **Step 1: Write the failing tests**

In `tests/ui/screens/tst_runs_screen.qml`, after `test_the_finished_rows_sit_under_the_status_chips_and_above_the_list` add:

```qml
  // ---- Show older (4.3)

  function test_entries_place_show_older_after_each_eligible_projects_last_run() {
    var s = make([]); if (!s) return
    var a = doneRuns(10, "/home/u/a", "alpha", "a")
    var b = doneRuns(2, "/home/u/b", "beta", "b")
    var c = doneRuns(10, "/home/u/c", "gamma", "c")
    var loose = [run("run-x-done9999", "done", null, {})]
    var groups = Runs.groupByProject(a.concat(b, loose))
    var runs = Runs.displayOrder(groups)
    var roots = [{ root: "/home/u/a", name: "alpha" }, { root: "/home/u/b", name: "beta" }, { root: "/home/u/c", name: "gamma" }]
    var errors = { "/home/u/c": "AmFailed: c" }
    var byProject = { "/home/u/a": a, "/home/u/b/": b, "/home/u/c": c, "": doneRuns(10, "", "", "x") }
    var history = { "/home/u/b/": page({ more: true }) }
    compare(shape(s.screen.entriesOf(groups, runs, roots, errors, "", {}, byProject, history, true)),
            "h0," + runIds(0, 10) + ",o0:/home/u/a,h1," + runIds(10, 2) + ",o1:/home/u/b/,r12,h2",
            "grouped: after a group's last run, the registry's spelling; none for the \"\" group or an error-only header")
    compare(shape(s.screen.entriesOf(groups, runs, roots, errors, "", {}, byProject, history, false)),
            "h0," + runIds(0, 10) + ",h1," + runIds(10, 2) + ",r12,h2", "none when it may not show")
    compare(shape(s.screen.entriesOf(groups, runs, roots, errors, "", {}, null, null, true)),
            "h0," + runIds(0, 10) + ",h1," + runIds(10, 2) + ",r12,h2", "none without maps")
    var flatGroups = Runs.groupByProject(b)
    compare(shape(s.screen.entriesOf(flatGroups, Runs.displayOrder(flatGroups), roots, errors, "/home/u/b", {}, byProject, history, true)),
            "r0,r1,o0:/home/u/b/", "flat: after the last run")
    compare(shape(s.screen.entriesOf([], [], roots, errors, "/home/u/c", {}, byProject, history, true)),
            "e,o0:/home/u/c", "flat with no run passing the chips: the error line, then the button")
  }

  function test_ten_terminal_snapshot_runs_offer_show_older_and_nine_do_not() {
    var a = doneRuns(10, "/home/u/a", "alpha", "a")
    var b = doneRuns(9, "/home/u/b", "beta", "b")
    var bLive = [tagged(run("run-b-live0001", "started", true, {}), "/home/u/b", "beta"),
                 tagged(run("run-b-live0002", "started", true, {}), "/home/u/b", "beta"),
                 tagged(run("run-b-live0003", "started", true, {}), "/home/u/b", "beta")]
    var s = make(a.concat(b, bLive)); if (!s) return
    s.runs.runsByProject = { "/home/u/a": a, "/home/u/b": b.concat(bLive) }
    wait(20)
    var button = H.find(s.screen, "runsShowOlder0")
    verify(button, "alpha's button")
    compare(button.visible, true)
    compare(button.text, "Show older")
    compare(H.find(s.screen, "runsShowOlder1"), null, "beta: 9 terminal runs plus live ones")
    var parked = tagged(run("run-b-park0004", "stopped", null, {}), "/home/u/b", "beta")
    s.runs.runsByProject = { "/home/u/a": a, "/home/u/b": b.concat(bLive, [parked]) }
    wait(20)
    verify(H.find(s.screen, "runsShowOlder1"), "a parked run is terminal: beta now has 10")
  }

  function test_a_history_entry_decides_over_the_snapshot_rule() {
    var a = doneRuns(10, "/home/u/a", "alpha", "a")
    var b = doneRuns(2, "/home/u/b", "beta", "b")
    var s = make(a.concat(b)); if (!s) return
    s.runs.runsByProject = { "/home/u/a": a, "/home/u/b": b }
    s.history.historyByProject = { "/home/u/b": page({ more: true }) }
    wait(20)
    verify(H.find(s.screen, "runsShowOlder0"), "alpha by its snapshot")
    verify(H.find(s.screen, "runsShowOlder1"), "beta by its entry's more")
    verify(topOf(s, "runRow11") < topOf(s, "runsShowOlder1"), "beta's after beta's last run")
    s.history.historyByProject = { "/home/u/a": page({ more: false }), "/home/u/b": page({ more: true }) }
    wait(20)
    verify(H.find(s.screen, "runsShowOlder0"), "only beta's now")
    compare(H.find(s.screen, "runsShowOlder1"), null, "alpha is exhausted despite 10 terminal runs")
    verify(topOf(s, "runRow11") < topOf(s, "runsShowOlder0"), "the one left is beta's")
  }

  function test_grouped_buttons_sit_between_a_groups_last_run_and_the_next_header() {
    var a = doneRuns(10, "/home/u/a", "alpha", "a")
    var b = doneRuns(10, "/home/u/b", "beta", "b")
    var c = doneRuns(1, "/home/u/c", "gamma", "c")
    var s = make(a.concat(b, c)); if (!s) return
    s.runs.runsByProject = { "/home/u/a": a, "/home/u/b": b, "/home/u/c": c }
    wait(20)
    verify(topOf(s, "runRow9") < topOf(s, "runsShowOlder0"), "after alpha's last run")
    verify(topOf(s, "runsShowOlder0") < topOf(s, "runGroup1"), "before beta's header")
    verify(topOf(s, "runRow19") < topOf(s, "runsShowOlder1"), "after beta's last run")
    verify(topOf(s, "runsShowOlder1") < topOf(s, "runGroup2"), "before gamma's header")
    compare(H.find(s.screen, "runsShowOlder2"), null, "gamma is not eligible")
  }

  function test_flat_under_a_project_filter_one_button_also_with_no_row() {
    var a = doneRuns(10, "/home/u/a", "alpha", "a")
    var b = doneRuns(2, "/home/u/b", "beta", "b")
    var s = make(a.concat(b)); if (!s) return
    s.runs.runsByProject = { "/home/u/a": a, "/home/u/b": b }
    s.history.historyByProject = { "/home/u/b": page({ more: true }) }
    s.runs.projectFilter = "/home/u/b"
    wait(20)
    compare(H.find(s.screen, "runGroup0"), null, "flat")
    verify(H.find(s.screen, "runsShowOlder0"))
    compare(H.find(s.screen, "runsShowOlder1"), null, "one button, the filtered project's")
    verify(topOf(s, "runRow1") < topOf(s, "runsShowOlder0"), "after the last row")
    tap(H.find(s.screen, "runsShowOlder0"))
    compare(s.history.showOlderCalls.join(","), "/home/u/b")
    s.runs.toggleRunFilter("parked")
    wait(20)
    compare(H.find(s.screen, "runRow0"), null)
    compare(H.find(s.screen, "runsMessage").text, "No Parked runs.")
    verify(H.find(s.screen, "runsShowOlder0"), "still offered with no row")
    verify(topOf(s, "runsMessage") < topOf(s, "runsShowOlder0"), "under the status line")
  }

  function test_show_older_passes_the_registry_spelling_and_a_doubled_root_gets_one_button() {
    var r = tagged(run("run-a-done0001", "done", null, {}), "/home/u/a", "alpha")
    var s = make([r]); if (!s) return
    s.runs.runsByProject = { "/home/u/a/": [r] }
    s.history.historyByProject = { "/home/u/a/": page({ more: true }) }
    wait(20)
    tap(H.find(s.screen, "runsShowOlder0"))
    compare(s.history.showOlderCalls.join(","), "/home/u/a/", "the key as the registry spells it")
    s.runs.runsByProject = { "/home/u/a": doneRuns(10, "/home/u/a", "alpha", "a"), "/home/u/a/": [r] }
    s.history.historyByProject = {}
    wait(20)
    verify(H.find(s.screen, "runsShowOlder0"))
    compare(H.find(s.screen, "runsShowOlder1"), null, "one button for the project")
    tap(H.find(s.screen, "runsShowOlder0"))
    compare(s.history.showOlderCalls.join(","), "/home/u/a/,/home/u/a", "the first own key that matches")
  }

  function test_show_older_is_hidden_under_live_with_am_missing_and_without_a_run_history() {
    var a = doneRuns(10, "/home/u/a", "alpha", "a")
    var live = tagged(run("run-a-live0001", "started", true, {}), "/home/u/a", "alpha")
    var s = make(a.concat([live])); if (!s) return
    s.runs.runsByProject = { "/home/u/a": a.concat([live]) }
    wait(20)
    verify(H.find(s.screen, "runsShowOlder0"))
    s.runs.toggleRunFilter("live")
    wait(20)
    verify(H.find(s.screen, "runRow0"), "alpha's live run is listed")
    compare(H.find(s.screen, "runsShowOlder0"), null, "nothing to page under Live")
    s.runs.toggleRunFilter("all")
    wait(20)
    verify(H.find(s.screen, "runsShowOlder0"), "back under All, with no new snapshot")
    s.runs.amStatus = "missing"
    wait(20)
    compare(H.find(s.screen, "runsShowOlder0"), null, "am missing")
    s.runs.amStatus = "ok"
    wait(20)
    verify(H.find(s.screen, "runsShowOlder0"))
    s.app.runHistory = null
    wait(20)
    compare(H.find(s.screen, "runsShowOlder0"), null, "no run history")
    verify(H.find(s.screen, "runRow0"), "the rows stay")
  }

  function test_show_older_takes_no_index_and_the_cursor_walks_runs_only() {
    var a = doneRuns(10, "/home/u/a", "alpha", "a")
    var b = doneRuns(10, "/home/u/b", "beta", "b")
    var s = make(a.concat(b)); if (!s) return
    s.runs.runsByProject = { "/home/u/a": a, "/home/u/b": b }
    wait(20)
    verify(H.find(s.screen, "runsShowOlder0"), "a button between the groups")
    for (var i = 0; i < 20; i++)
      compare(H.find(s.screen, "runRowId" + i).text, Runs.runSubtitle(s.runs.filteredRuns[i]), "row " + i)
    compare(H.find(s.screen, "runRow20"), null)
    s.nav.cursorIndex = 19
    for (var j = 0; j < 20; j++) compare(H.find(s.screen, "runRow" + j).hasCursor, j === 19, "row " + j)
    var runsOnly = shape(s.screen.entries).split(",").filter(function(x) { return x.charAt(0) === "r" }).join(",")
    compare(runsOnly, runIds(0, 20), "the same run indexes as without the buttons")
  }

  function test_show_older_is_not_a_row() {
    var a = [tagged(run("run-a-done0001", "done", null, {}), "/home/u/a", "alpha")]
    var b = [tagged(run("run-b-done0002", "done", null, {}), "/home/u/b", "beta")]
    var s = make(a.concat(b)); if (!s) return
    s.runs.runsByProject = { "/home/u/a": a, "/home/u/b": b }
    s.history.historyByProject = { "/home/u/a": page({ more: true }), "/home/u/b": page({ more: true }) }
    wait(20)
    var button = H.find(s.screen, "runsShowOlder0")
    verify(button)
    compare(button.hasCursor, undefined, "not a ListRow")
    mouseMove(H.find(s.screen, "runChips"), 1, 1)
    s.navi.hovered = -1
    mouseMove(button, button.width / 2, button.height / 2)
    compare(s.navi.hovered, -1, "hovering it moves no cursor")
    tap(button)
    compare(s.navi.opened, "", "it opens no run")
    compare(s.history.showOlderCalls.join(","), "/home/u/a", "it asks the history once")
  }

  // Review Focus 2.
  function test_garbage_history_and_snapshot_maps_fall_back_and_do_not_throw() {
    var a = doneRuns(10, "/home/u/a", "alpha", "a")
    var s = make(a); if (!s) return
    s.runs.runsByProject = { "/home/u/a": a }
    var cases = [[{ "/home/u/a": null }, true, "a null entry is no entry"],
                 [{ "/home/u/a": "x" }, true, "a string entry is no entry"],
                 [{ "/home/u/a": { loading: "yes", more: 1, error: 7 } }, false, "an entry with no true flag and no error"],
                 [null, true, "no history map"],
                 ["x", true, "a history map that is not an object"]]
    for (var c = 0; c < cases.length; c++) {
      s.history.historyByProject = cases[c][0]
      wait(20)
      compare(!!H.find(s.screen, "runsShowOlder0"), cases[c][1], cases[c][2])
    }
    s.history.historyByProject = {}
    s.runs.runsByProject = { "/home/u/a": "nope" }
    wait(20)
    compare(H.find(s.screen, "runsShowOlder0"), null, "a list that is not an array counts 0")
    s.runs.runsByProject = { "/home/u/a": [null, 3, "x", []].concat(a.slice(0, 9)) }
    wait(20)
    compare(H.find(s.screen, "runsShowOlder0"), null, "non-runs are not terminal: 9")
    s.runs.runsByProject = null
    wait(20)
    compare(H.find(s.screen, "runsShowOlder0"), null, "no snapshot map")
    verify(H.find(s.screen, "runRow0"), "the rows stay")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/screens/tst_runs_screen.qml 2>&1 | grep -E "^(FAIL|Totals)"`
Expected: the ten new tests FAIL (no `showOlder` entries, no `runsShowOlder0`); `test_garbage_…` fails at its first `true` case. All earlier tests PASS.

- [ ] **Step 3: Implement the eligibility, the entries and the button**

In `ui/screens/RunsScreen.qml` replace

```qml
  // What the list draws, in order (entriesOf).
  readonly property var entries: screen.entriesOf(screen.app.runs.groups, screen.app.runs.filteredRuns,
    screen.app.runs.projectRoots, screen.app.runs.projectErrors, screen.app.runs.projectFilter,
    screen.app.runTitles.titleStatus)
```

with

```qml
  // The snapshot keeps at most this many terminal runs per project
  // (TERMINAL_LIMIT in core/backend/common/am_runs.py): a project listing
  // this many may have older ones.
  readonly property int terminalLimit: 10
  // The run history; null when the app has none.
  readonly property var runHistory: screen.app.runHistory !== undefined && screen.app.runHistory !== null
    ? screen.app.runHistory : null
  // Show older may show at all: am is present, there is a run history and
  // the chip has statuses to page (Runs.historyStatuses; none under Live).
  readonly property bool canShowOlder: !screen.amMissing && screen.runHistory !== null
    && Runs.historyStatuses(screen.app.runs.runFilter, screen.app.runs.finishedState).length > 0

  // What the list draws, in order (entriesOf).
  readonly property var entries: screen.entriesOf(screen.app.runs.groups, screen.app.runs.filteredRuns,
    screen.app.runs.projectRoots, screen.app.runs.projectErrors, screen.app.runs.projectFilter,
    screen.app.runTitles.titleStatus, screen.app.runs.runsByProject,
    screen.runHistory !== null ? screen.runHistory.historyByProject : null, screen.canShowOlder)
```

Before the comment `// The list's entries, scalar values only (a Repeater converts nested ones):` add:

```qml
  // The own key of `byProject` ({root: runs}) whose rootKey is `root`'s, the
  // first in key order; "" when `root` is "", `byProject` is not an object or
  // no key matches.
  function historyKeyOf(byProject, root) {
    var want = screen.rootKey(root)
    if (want === "" || byProject === null || typeof byProject !== "object") return ""
    var keys = Object.keys(byProject)
    for (var k = 0; k < keys.length; k++) {
      if (screen.rootKey(keys[k]) === want) return keys[k]
    }
    return ""
  }

  // The entry `history` ({root: {runs, more, loading, error}}) holds under
  // its own key `key`; null when there is none or it is not an object.
  function historyEntryOf(history, key) {
    if (key === "" || history === null || typeof history !== "object" || !Runs.hasKey(history, key)) return null
    var entry = history[key]
    return entry !== null && typeof entry === "object" ? entry : null
  }

  // How many runs of `list` are terminal: done, escalated, cancelled or
  // parked; 0 when `list` is not array-like.
  function terminalCountOf(list) {
    var n = 0
    for (var i = 0; i < screen.sizeOf(list); i++) {
      var state = Runs.runState(list[i])
      if (state === "done" || state === "escalated" || state === "cancelled" || state === "parked") n++
    }
    return n
  }

  // Whether the project under the own key `key` of `byProject` offers Show
  // older: its `history` entry is loading, carries an error sentence or says
  // more; with no entry, its snapshot list holds terminalLimit terminal runs
  // or more. False for key "".
  function offersOlder(byProject, history, key) {
    if (key === "") return false
    var entry = screen.historyEntryOf(history, key)
    if (entry !== null)
      return entry.loading === true || (typeof entry.error === "string" && entry.error !== "") || entry.more === true
    return screen.terminalCountOf(byProject[key]) >= screen.terminalLimit
  }

```

Replace the whole `entriesOf` comment and function (from `// The list's entries, scalar values only (a Repeater converts nested ones):` through the function's closing `}` before `// A dead or parked run's state`) with:

```qml
  // The list's entries, scalar values only (a Repeater converts nested ones):
  // { kind: "header", g, name, counts, error, titlesUnavailable },
  // { kind: "run", i } with i the run's index in `runs` (filteredRuns, which
  // is displayOrder of `groups`), { kind: "projectError", text } and
  // { kind: "showOlder", k, root }.
  // Under a project filter: the filtered project's error when it has one,
  // then every run, flat, then its Show older. Otherwise each group of
  // `groups` in turn: a header unless its root is "", then its runs, then its
  // Show older unless its root is ""; then, for each root of the registry
  // `roots` (in order, once) with an error and no group, a header with no
  // counts, no runs and no Show older. g counts the headers from 0; name is
  // the project's name, else its root; error is projectError's;
  // titlesUnavailable is titlesUnavailableOf `status` ({root: title status})
  // for its root. A Show older is there only while `older` is true and
  // offersOlder(byProject, history, key) holds for key, historyKeyOf
  // `byProject` for the project's root; root is that key and k counts the
  // Show older entries from 0. No Show older takes a run index.
  function entriesOf(groups, runs, roots, errors, filter, status, byProject, history, older) {
    var out = []
    var k = 0
    if (typeof filter === "string" && filter !== "") {
      var flatError = screen.projectError(errors, filter)
      if (flatError !== "") out.push({ kind: "projectError", text: flatError })
      for (var r = 0; r < screen.sizeOf(runs); r++) out.push({ kind: "run", i: r })
      var flatKey = older === true ? screen.historyKeyOf(byProject, filter) : ""
      if (screen.offersOlder(byProject, history, flatKey)) out.push({ kind: "showOlder", k: k++, root: flatKey })
      return out
    }
    var listed = Object.create(null)
    var g = 0
    var i = 0
    for (var n = 0; n < screen.sizeOf(groups); n++) {
      var group = groups[n]
      var root = group.project.root
      if (root !== "") {
        listed[root] = true
        out.push({ kind: "header", g: g++, name: group.project.name !== "" ? group.project.name : root,
                   counts: screen.countsText(group.counts), error: screen.projectError(errors, root),
                   titlesUnavailable: screen.titlesUnavailableOf(status, root) })
      }
      for (var j = 0; j < screen.sizeOf(group.runs); j++) out.push({ kind: "run", i: i++ })
      var olderKey = older === true ? screen.historyKeyOf(byProject, root) : ""
      if (screen.offersOlder(byProject, history, olderKey)) out.push({ kind: "showOlder", k: k++, root: olderKey })
    }
    for (var e = 0; e < screen.sizeOf(roots); e++) {
      var project = roots[e]
      if (project === null || typeof project !== "object") continue
      var key = screen.rootKey(project.root)
      if (key === "" || listed[key]) continue
      var error = screen.projectError(errors, key)
      if (error === "") continue
      listed[key] = true
      out.push({ kind: "header", g: g++, name: typeof project.name === "string" && project.name !== "" ? project.name : key,
                 counts: "", error: error, titlesUnavailable: screen.titlesUnavailableOf(status, key) })
    }
    return out
  }
```

In `component RunEntry`, replace the comment and `sourceComponent` binding

```qml
  // One entry of `entries`: a project's header, a run's row or the filtered
  // project's error line.
```

with

```qml
  // One entry of `entries`: a project's header, a run's row, the filtered
  // project's error line or a project's Show older.
```

and

```qml
      : entry.fact.kind === "projectError" ? projectErrorC
      : null
```

with

```qml
      : entry.fact.kind === "projectError" ? projectErrorC
      : entry.fact.kind === "showOlder" ? olderC
      : null
```

Inside `RunEntry`, after the `projectErrorC` `Component { … }` block, add:

```qml

    Component {
      id: olderC
      OlderRuns {
        k: typeof entry.fact.k === "number" ? entry.fact.k : 0
        root: typeof entry.fact.root === "string" ? entry.fact.root : ""
      }
    }
```

After the closing `}` of `component RunGroupHeader` (before `// A run's row; `index` is the run's position in filteredRuns.`) add:

```qml
  // A project's Show older: asks the run history for the next older page of
  // the project under `root`, its runsByProject key. Not a row: no cursor,
  // no hover, no index.
  component OlderRuns: Column {
    id: older
    property int k: 0
    property string root: ""

    width: screen.width
    leftPadding: Style.space(10)
    rightPadding: Style.space(10)
    spacing: Style.space(2)

    UI.ActionButton {
      objectName: "runsShowOlder" + older.k
      theme: screen.theme
      text: "Show older"
      onClicked: if (screen.runHistory !== null) screen.runHistory.showOlder(older.root)
    }
  }

```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/screens/tst_runs_screen.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError"`
Expected: `0 failed`, no error lines.

- [ ] **Step 5: Run the full suite**

Run: `bash tests/run.sh`
Expected: exit status 0 (`tst_runs_flow.qml` and `tst_runs_real_data.qml` show no button: their `runsByProject` lists fewer than 10 terminal runs).

- [ ] **Step 6: Commit**

```bash
git add ui/screens/RunsScreen.qml tests/ui/screens/tst_runs_screen.qml
git commit -m "feat(runs): Show older after each project's last run asks the run history for that project's older page"
```

---

### Task 5: Show older while loading and after a failed page; real-store wiring

**Files:**
- Modify: `ui/screens/RunsScreen.qml` (`component OlderRuns`)
- Test: `tests/ui/screens/tst_runs_screen.qml`, `tests/ui/tst_runs_flow.qml`

**Interfaces:**
- Consumes: Task 4's `OlderRuns`, `historyEntryOf(history, key)`, `runHistory`; `app.runHistory.historyByProject[root].loading` / `.error`.
- Produces: `OlderRuns.page`, `OlderRuns.loading`, `OlderRuns.error`; caption `runsShowOlderError<k>`.

- [ ] **Step 1: Write the failing screen tests**

In `tests/ui/screens/tst_runs_screen.qml`, after `test_garbage_history_and_snapshot_maps_fall_back_and_do_not_throw` add:

```qml
  // Review Focus 5.
  function test_a_page_in_flight_reads_loading_and_takes_no_click() {
    var a = [tagged(run("run-a-done0001", "done", null, {}), "/home/u/a", "alpha")]
    var s = make(a); if (!s) return
    s.runs.runsByProject = { "/home/u/a": a }
    s.history.historyByProject = { "/home/u/a": page({ loading: true }) }
    wait(20)
    var button = H.find(s.screen, "runsShowOlder0")
    compare(button.text, "Loading older runs…")
    compare(button.enabled, false)
    compare(H.find(s.screen, "runsShowOlderError0").visible, false)
    tap(button)
    compare(s.history.showOlderCalls.length, 0, "a click while loading calls nothing")
    s.history.historyByProject = { "/home/u/a": page({ more: true }) }
    wait(20)
    compare(H.find(s.screen, "runsShowOlder0").text, "Show older", "the page landed with more")
    compare(H.find(s.screen, "runsShowOlder0").enabled, true)
    s.history.historyByProject = { "/home/u/a": page({ more: false }) }
    wait(20)
    compare(H.find(s.screen, "runsShowOlder0"), null, "exhausted")
  }

  // Review Focus 1.
  function test_a_failed_page_shows_its_sentence_in_urgent_and_stays_clickable() {
    var a = [tagged(run("run-a-done0001", "done", null, {}), "/home/u/a", "alpha")]
    var s = make(a); if (!s) return
    s.runs.runsByProject = { "/home/u/a": a }
    s.history.historyByProject = { "/home/u/a": page({ more: false, error: "am failed" }) }
    wait(20)
    var button = H.find(s.screen, "runsShowOlder0")
    verify(button, "a failed page keeps the button even with more false")
    compare(button.text, "Show older")
    compare(button.enabled, true)
    var line = H.find(s.screen, "runsShowOlderError0")
    compare(line.visible, true)
    compare(line.text, "am failed")
    verify(Qt.colorEqual(line.color, s.screen.theme.urgent), "drawn urgent")
    compare(line.wrapMode, Text.WordWrap)
    verify(topOf(s, "runsShowOlder0") < topOf(s, "runsShowOlderError0"), "under the button")
    verify(H.find(s.screen, "runRow0"), "the listed rows stay")
    tap(button)
    compare(s.history.showOlderCalls.join(","), "/home/u/a", "retry")
  }
```

- [ ] **Step 2: Write the failing flow test**

In `tests/ui/tst_runs_flow.qml`, after `test_the_finished_chip_and_its_rows_set_the_real_store` add:

```qml
  function test_show_older_reads_the_real_run_history_and_a_chip_change_drops_its_page() {
    var p = make(); if (!p) return
    p.shortcuts.handleGlobalKey({ modifiers: Qt.ControlModifier, key: Qt.Key_6 })
    wait(50)
    p.app.runs.runsByProject = { "/home/u/a": [] }
    p.app.runHistory.historyByProject = { "/home/u/a": { runs: [], more: false, loading: true, error: "" } }
    wait(20)
    var button = H.find(p, "runsShowOlder0")
    verify(button, "the real store's entry is read")
    compare(button.text, "Loading older runs…")
    compare(button.enabled, false)
    H.find(p, "runChipattention").clicked()
    wait(20)
    compare(Object.keys(p.app.runHistory.historyByProject).length, 0, "the real store dropped the page")
    compare(H.find(p, "runsShowOlder0"), null, "back to the snapshot rule: no terminal runs")
  }
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/screens/tst_runs_screen.qml 2>&1 | grep -E "^(FAIL|Totals)|^   (Actual|Expected)"`
Expected: both new tests FAIL (text is `Show older` while loading; `runsShowOlderError0` not found).

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/tst_runs_flow.qml RunsFlow::test_show_older_reads_the_real_run_history_and_a_chip_change_drops_its_page 2>&1 | grep -E "^(FAIL|Totals)|^   (Actual|Expected)"`
Expected: FAIL on `Loading older runs…` (actual `Show older`).

- [ ] **Step 4: Implement**

In `ui/screens/RunsScreen.qml` replace the whole `component OlderRuns` (its comment included) with:

```qml
  // A project's Show older: asks the run history for the next older page of
  // the project under `root`, its runsByProject key. While that page is in
  // flight it reads `Loading older runs…` and takes no click; when the last
  // page failed, its sentence shows under it in urgent and it stays
  // clickable. Not a row: no cursor, no hover, no index.
  component OlderRuns: Column {
    id: older
    property int k: 0
    property string root: ""
    // The project's history entry, read live; null when it has none.
    readonly property var page: screen.historyEntryOf(screen.runHistory !== null ? screen.runHistory.historyByProject : null, older.root)
    readonly property bool loading: older.page !== null && older.page.loading === true
    readonly property string error: older.page !== null && typeof older.page.error === "string" ? older.page.error : ""

    width: screen.width
    leftPadding: Style.space(10)
    rightPadding: Style.space(10)
    spacing: Style.space(2)

    UI.ActionButton {
      objectName: "runsShowOlder" + older.k
      theme: screen.theme
      enabled: !older.loading
      text: older.loading ? "Loading older runs…" : "Show older"
      onClicked: if (!older.loading && screen.runHistory !== null) screen.runHistory.showOlder(older.root)
    }

    UI.ThemedText {
      objectName: "runsShowOlderError" + older.k
      variant: "caption"
      theme: screen.theme
      width: Math.max(0, older.width - older.leftPadding - older.rightPadding)
      visible: text !== ""
      text: older.error
      color: screen.theme.urgent
      wrapMode: Text.WordWrap
    }
  }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/screens/tst_runs_screen.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError"`
Expected: `0 failed`.

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/tst_runs_flow.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError"`
Expected: `0 failed`.

- [ ] **Step 6: Run the full suite**

Run: `bash tests/run.sh`
Expected: exit status 0.

- [ ] **Step 7: Commit**

```bash
git add ui/screens/RunsScreen.qml tests/ui/screens/tst_runs_screen.qml tests/ui/tst_runs_flow.qml
git commit -m "feat(runs): Show older reads Loading older runs… while its page is in flight and a failed page's sentence in urgent"
```

---

### Task 6: Header comment and architecture docs

**Files:**
- Modify: `ui/screens/RunsScreen.qml:10-29` (header comment)
- Modify: `docs/architecture.md:133` (FilterableList), `:168` (run screens paragraph)
- Test: `tests/architecture/test_run_store_docs.py`, `tests/architecture/test_layers.py`, `tests/architecture/test_icon_glyphs.py` (unchanged; must stay green)

**Interfaces:**
- Consumes: everything above. Produces: documentation only.

- [ ] **Step 1: Rewrite the RunsScreen header comment**

In `ui/screens/RunsScreen.qml` replace the comment from `// The Runs section: every registered project's am runs, grouped by project` through `// Ages are read against the clock once per snapshot: there is no timer.` with:

```qml
// The Runs section: every registered project's am runs, grouped by project
// with a header each (name; live, parked and needs-attention counts; the
// project's snapshot error; a dim `titles unavailable` while its titles
// cannot be read), flat with no header under a project filter. Each
// run is one row (state glyph; title, from the run's own project's map in
// app.runTitles; short id in dim; done/total, current phase, age) whose index
// is its position in the store's filteredRuns, the one list
// the cursor walks; headers are not cursor targets. A project chip row (All
// projects, This project when one is open, one chip per project with runs,
// with run counts) sits above the status chips, hidden when only one project
// has runs and none is open; clicking one asks the store to toggle its
// project filter. Needs attention / Live / Parked / Finished / All chips
// apply across groups and carry the store's runFilterCounts -- clicking the
// active chip means All again. Under them, while am is present, a state row
// (All finished / Done / Escalated / Cancelled) under Finished and an age
// row (Today / 7 days / All time) under Finished and All ask the store to
// toggle its finished state and age. After each project's last run (after
// the last run under a project filter) a Show older button -- not a row,
// never a cursor target -- asks app.runHistory for that project's next older
// page; it shows while am is present, the chip has statuses to page and the
// project's history entry is loading, failed or has more, or, with no entry,
// its snapshot lists terminalLimit terminal runs; it reads `Loading older
// runs…` and takes no click while its page is in flight, and a failed
// page's sentence shows under it in urgent. A footer says whether the runs
// are watched. The row with the cursor shows Open project for a run of a
// registered project other than the open one; the button asks the navigator
// to choose that project. It reads the run store, the run history, the run
// titles and the project registry and asks the navigator to open a run,
// choose a project or move the cursor, the run titles to read every
// project's titles again and the run history for older runs; it owns no
// state of its own.
// Ages are read against the clock once per snapshot: there is no timer.
```

- [ ] **Step 2: Update `docs/architecture.md`**

On line 133 replace

```
`ListStatus` (loading/error/empty), `FilterableList`, `TextAreaBox`,
```

with

```
`ListStatus` (loading/error/empty), `FilterableList` (its optional `chipsFooter` is made once under the chip row and above the status line, shown under the chip row's rule while `chipsFooterShown`; hidden, it takes no height and no gap), `TextAreaBox`,
```

On line 168 replace

```
The run screens read `app.runs` and `app.runControl` (`BoardScreen` and `GraphScreen` only `app.runs`; `RunsScreen`, `RunDetailScreen` and `CardDetailScreen` also `app.runTitles`) and never import `core/stores`.
```

with

```
The run screens read `app.runs` and `app.runControl` (`BoardScreen` and `GraphScreen` only `app.runs`; `RunsScreen`, `RunDetailScreen` and `CardDetailScreen` also `app.runTitles`; `RunsScreen` also `app.runHistory`) and never import `core/stores`.
```

and, on the same line, replace

```
under it the Needs attention / Live / Parked / All chips carry `Runs.runFilterCounts` of the runs within the project filter.
```

with

```
under it the Needs attention / Live / Parked / Finished / All chips carry `app.runs.runFilterCounts` (the listed runs, snapshot and loaded history, within the project filter; All has no count). Between those chips and the list, in `FilterableList`'s `chipsFooter` and hidden while am is missing, a state row (`runStateChips`: All finished / Done / Escalated / Cancelled, through `toggleFinishedState`) shows under Finished and an age row (`runAgeChips`: Today / 7 days / All time, through `toggleFinishedAge`) under Finished and All. After each project group's last run -- after the last run under a project filter, even when no run passes the chips; never for an error-only header -- a `Show older` button (`runsShowOlder<k>`) asks `app.runHistory.showOlder(root)` with the project's `runsByProject` key (roots compared without trailing `/`); it is not a row, takes no cursor index and never shifts one. It shows while am is present, `app.runHistory` exists and `Runs.historyStatuses` of the chip is not empty (never under Live), and then when the project's `app.runHistory.historyByProject` entry is loading, carries an error or says `more`, or, with no entry, when its snapshot lists 10 terminal runs (done, escalated, cancelled or parked: the snapshot's per-project cap); a page with `more` false and no error hides it. While the page is in flight it reads `Loading older runs…` and takes no click; a failed page's sentence shows under it in `urgent` (`runsShowOlderError<k>`) and it stays clickable.
```

- [ ] **Step 3: Run the architecture tests**

Run: `python3 -m pytest tests/architecture -q` (or `uv run --with pytest python3 -m pytest tests/architecture -q` when `python3` has no pytest)
Expected: all passed (`test_run_store_docs.py`, `test_layers.py`, `test_icon_glyphs.py` included).

- [ ] **Step 4: Run the full suite**

Run: `bash tests/run.sh`
Expected: exit status 0; every QML file `0 failed`; no TypeError/ReferenceError/non-existent/Unable to assign lines.

- [ ] **Step 5: Commit**

```bash
git add ui/screens/RunsScreen.qml docs/architecture.md
git commit -m "docs(runs): the Runs screen's Finished chip, its state and age rows and Show older"
```

---

## Self-review against the spec

- Validated before hand-off: every code block of Tasks 1–6 was applied to a scratch copy of this worktree; `bash tests/run.sh` exited 0 (`tst_runs_screen.qml` 122 passed, `tst_filterable_list.qml` 13, `tst_runs_flow.qml` 42, `tst_runs_real_data.qml` 9, architecture tests green).

- B1.1–B1.4 → Task 2 (order via model ids, counts source via `countsOverride`, `No Finished runs.`, click/active via existing chip tests plus `test_the_finished_chip_filters_and_names_its_empty_list`).
- B2.1–B2.4, B3.1–B3.4 → Task 3 (labels, no counts — the models carry no `count`, visibility per filter and am missing, active, click with id unchanged).
- B4 → Tasks 1 and 3 (slot; `chipsFooterShown` replaces the latching height rule — see Deviation).
- B5.1 → Task 4 (grouped, flat, flat with no row, error-only header, `""` root). B5.2 → Task 4 (`historyKeyOf`, registry spelling, doubled root). B5.3 → Task 4 (am missing, null history, Live, entry flags, 10 vs 9, parked counts). B5.4–B5.6 → Task 5. B5.7 → Task 4 (`runRow<i>` ↔ `filteredRuns`, cursor, hover, click opens nothing). B5.8 → objectNames in Tasks 4–5.
- B6 → Task 4 (`entriesOf` pure, scalar entry, `RunEntry` mapping; unknown kinds still `null`).
- B7 → Task 6.
- Spec tests 1–19: 1–2 Task 2; 3–6 Task 3; 7–10, 13–16 Task 4; 11–12 Task 5; 17 Task 3; 18 by the full-suite step of every task; 19 Task 6 Step 3.
- Edge table: every row has a test (am missing, null history, Live, trailing `/`, in flight, failed, `more: false`, filter change drops pages — Task 5 flow test, 9 terminal runs).
<!-- task-pipeline: validated -->
