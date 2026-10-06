# 4.5 RunsScreen: footer shows the announced am version and schema (card a9c44f17)

This narrows `docs/superpowers/specs/2026-10-05-align-run-model-design.md`
(called "the parent" below). It draws on these parts of the parent:
- Decision 8 (line 172: "Both cancel spellings, both hello schemas").
- "Both spellings, both schemas" (lines 286-304), in particular the `RunStore`
  bullet (lines 301-302: `amSchema` is 0 until a hello arrives, `amVersion`
  from that line, both reset when the watch stops or the project switches) and
  the `RunsScreen` footer bullet (lines 303-304: `am <version> · schema N ·
  watching` while a hello is known, the S1 mockup, else `am · watching` /
  `am · not watching`).
- "Not changed" (line 314: screen layouts do not change).
- Work breakdown item 4 (lines 329-330) names "the footer" as part of this
  story; item 5 (line 331) owns the docs.

The S1 mockup the parent cites is
`docs/superpowers/specs/2026-10-03-am-run-monitor-design.md:198`:
`am 0.1.0 · schema 1 · watching`.

The parent story is 27d8a320. This card is blocked by 4.4 (41301b87), which is
already on this branch.

## Starting point

- `core/stores/RunStore.qml:31-32` has `property int amSchema: 0` (0 =
  unknown) and `property string amVersion: ""` (`""` = unknown). They are set
  from the current watch's hello and reset to `0` / `""` whenever the watch
  stops, exits or restarts (card 4.4). `amSchema` is never negative or
  fractional: it is 0 or an integer of 1 or more.
- `ui/screens/RunsScreen.qml:139-153` is the footer, a `UI.ThemedText` with
  `objectName: "runsFooter"`. Its text today is, in order of precedence:
  1. `app.runs.flashText` when it is not `""`;
  2. `app.runs.lastError` when `amStatus` is `"error"` and `lastError` is not
     `""`;
  3. otherwise the hardcoded `"am · schema 1 · "` followed by `watching` or
     `not watching` (from `app.runs.watching`), line 151.

  Its `visible` binding (line 144) is
  `(!amMissing && amStatus !== "schema") || flashText !== ""`.
- `tests/ui/screens/tst_runs_screen.qml` drives the screen with a fake store
  (`runsC`, lines 26-62). That fake has no `amSchema` / `amVersion`. Three
  assertions hardcode the old line: lines 317 and 320
  (`test_the_footer_says_whether_the_runs_are_watched`) and line 492
  (`test_a_flash_takes_the_footer_and_then_gives_it_back`).
- `tests/fixtures/am/watch-hello.json` holds the real am hello: `am: "0.1.0"`,
  `schema: 1`.

## Required behaviour

1. **The watch line (precedence 3) reads the announced hello.** With
   `v = app.runs.amVersion`, `n = app.runs.amSchema` and `w` = `watching`
   when `app.runs.watching` is true, else `not watching`:

   | `amSchema` | `amVersion` | footer text |
   |---|---|---|
   | `0` | anything | `am · <w>` |
   | `n ≥ 1` | non-empty `v` | `am <v> · schema <n> · <w>` |
   | `n ≥ 1` | `""` | `am · schema <n> · <w>` |

   Examples: `am 0.1.0 · schema 1 · watching`, `am 0.2.0 · schema 2 · not
   watching`, `am · watching`, `am · not watching`, `am · schema 2 · watching`.

   The separator is ` · ` (space, U+00B7 middle dot, space), exactly as today.
   `<n>` is printed as a plain integer (`2`, never `2.0`).

   The third row is a decision this spec makes: the parent (lines 303-304) and
   the card describe the known-hello line only as `am <version> · schema N`.
   Read literally, an empty version would give `am  · schema N` with two
   spaces. Instead the version and its space are left out. The store can reach
   this row: 4.4 sets `amVersion` to `""` when the hello's `am` is not a string,
   while still taking a valid `schema`.

   The `watching` vs `amSchema` combinations are independent: the footer
   prints what the store says and does not cross-check them (for example
   `amSchema 1` with `watching false` reads `am 0.1.0 · schema 1 · not
   watching`).

2. **The text follows the store live.** When `amSchema`, `amVersion` or
   `watching` change while the screen is shown, the footer text changes with
   them, with no reload of the screen. This holds both ways: a hello arriving
   (0 → n) and a reset (n → 0).

3. **Precedence unchanged.** A non-empty `flashText` still wins over
   everything. With no flash, `amStatus === "error"` with a non-empty
   `lastError` still shows `lastError`. Only when neither applies does the
   watch line of rule 1 show. When a flash or the error clears, the footer
   falls back to the watch line of rule 1 for the current
   `amSchema` / `amVersion` / `watching`.

4. **Visibility unchanged.** The `visible` binding stays exactly as it is
   (line 144): hidden when am is missing or the schema banner shows, unless a
   flash is showing. `amSchema` / `amVersion` have no effect on visibility.

5. **Nothing else on the screen changes.** No other object, layout, binding,
   objectName or keyboard behaviour changes (parent line 314). The screen still
   reads only `app.runs` and does not import `core/stores`
   (`docs/architecture.md:169`).

6. **Comments state the contract only.** The comment above the footer
   (lines 139-140) may say the watch line names the announced am version and
   schema when known. No mention of am's migration, cards, plans or history.

## Error paths

- `amSchema` 0 with a non-empty `amVersion` (the store never does this, since
  both are written from the same line and reset together, but the footer must
  not depend on that): shows `am · <w>`. The version is shown only alongside a
  known schema.
- The screen must produce no QML warning (`TypeError`, `ReferenceError`,
  `Unable to assign`, `non-existent`) for any row of rule 1. `tests/run.sh`
  fails on those.
- An error or flash line is never prefixed or suffixed with the am version or
  schema.

## Tests

All new and changed tests are in `tests/ui/screens/tst_runs_screen.qml`.
**Tier: QML UI screen test** (qmltestrunner via `tests/run.sh`), because the
contract is the text of one bound `ThemedText` that depends on a store's
properties. A screen test with a fake store pins exactly that, with no am
process, no real `RunStore` and no panel. The store side (how `amSchema` /
`amVersion` get their values and when they reset) is already pinned by 4.4 in
`tests/core/stores/tst_run_store.qml` and is not re-tested here.

Fake store change: add `property int amSchema: 0` and
`property string amVersion: ""` to `runsC`, so it matches the real store's
defaults.

Changed tests (old literal → new expected text under the fake's defaults,
`amSchema 0`):
- `test_the_footer_says_whether_the_runs_are_watched`: `am · watching`, then
  `am · not watching` after `watching = false`, and still visible.
- `test_a_flash_takes_the_footer_and_then_gives_it_back` (line 492): after the
  flash clears, `am · watching`. The rest of that test is unchanged.

New tests:
1. `test_the_footer_names_am_and_schema_1_from_the_hello`: set
   `amVersion "0.1.0"` and `amSchema 1` (the real fixture's values); expect
   `am 0.1.0 · schema 1 · watching`; set `watching = false`; expect
   `am 0.1.0 · schema 1 · not watching`.
2. `test_the_footer_names_schema_2_from_the_hello`: `amVersion "0.2.0"`,
   `amSchema 2`; expect `am 0.2.0 · schema 2 · watching`.
3. `test_the_footer_without_a_hello_names_no_schema`: defaults give
   `am · watching`. Then set `amSchema 1` and `amVersion "0.1.0"` and check
   the full line, then set `amSchema 0` and `amVersion ""` (a reset) and check
   it goes back to `am · watching` (rule 2, both directions).
4. `test_the_footer_leaves_out_an_unknown_version`: `amSchema 2`,
   `amVersion ""` → `am · schema 2 · watching` (rule 1, third row).
5. `test_the_footer_shows_no_version_without_a_schema`: `amSchema 0`,
   `amVersion "0.1.0"` → `am · watching` (error path 1).
6. `test_flash_and_error_still_win_over_the_announced_hello`: with
   `amSchema 2`, `amVersion "0.2.0"`: a flash shows the flash; clearing it
   shows `am 0.2.0 · schema 2 · watching`; `amStatus "error"` with
   `lastError "AmFailed: boom"` shows `AmFailed: boom`; a flash over the error
   shows the flash; clearing the flash shows the error again; `amStatus "ok"`
   shows the watch line again (rule 3).
7. `test_the_hello_does_not_unhide_the_footer`: `amSchema 1`,
   `amVersion "0.1.0"`; with `amStatus "missing"` the footer is not visible;
   with `amStatus "schema"` it is not visible (rule 4).

Existing tests that must pass unchanged: everything else in
`tst_runs_screen.qml` (including the missing-am and schema-banner tests at
lines ~294-345), `tests/architecture` (no new component, no glyph), and the
whole `bash tests/run.sh`.

## Files

- Modify: `ui/screens/RunsScreen.qml` (footer `text` binding, line 151; the
  comment at lines 139-140 only if it needs the contract wording).
- Modify: `tests/ui/screens/tst_runs_screen.qml` (fake store properties;
  the three literals; the new tests above).

No other file changes. One task with its own test cycle is enough: the
deliverable is one binding.

## Verification

`bash tests/run.sh` green.

## Out of scope

- `RunStore`'s `amSchema` / `amVersion` (how they are read and reset): card 4.4,
  done.
- `runs.js`, `runs-snapshot.py`, `runs-watch.py`: cards 4.1-4.3, done.
- `README.md:154` and `docs/architecture.md:169`, which still quote
  `am · schema 1 · watching`, and `README.md:258` ("am must speak journal
  schema 1"): docs are work breakdown item 5 (parent line 331), "written from
  the implementation". This card does not edit them.
- The schema-mismatch banner, the stale banner, the warning line, Run detail,
  the sidebar and any other surface: no change.
- Showing the version or schema anywhere other than the Runs footer.
