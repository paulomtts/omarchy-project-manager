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
