# 4.5 RunsScreen: footer shows the announced am version and schema: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Runs footer's watch line reads `am <version> · schema N · watching` from the store's announced hello (`app.runs.amVersion` / `app.runs.amSchema`), falling back to `am · watching` / `am · not watching` while no hello is known.

**Architecture:** One change to the `text` binding of the `runsFooter` `UI.ThemedText` in `ui/screens/RunsScreen.qml`: the hardcoded `"am · schema 1 · "` becomes `"am"`, plus `" <version>"` (only when the schema is known and the version is non-empty), plus `" · schema <n>"` (only when `amSchema > 0`), plus `" · watching"` / `" · not watching"`. Precedence (flash, then error, then the watch line) and the `visible` binding stay as they are. The screen test's fake store gains the two properties with the real store's defaults.

**Tech Stack:** QML (Qt 6 / Quickshell), JavaScript expressions in QML bindings, `qmltestrunner` driven by `tests/run.sh`, screen tests with a fake store (`tests/ui/screens/tst_runs_screen.qml`).

**Spec:** `docs/superpowers/specs/4-5-runsscreen-footer-a9c44f17.md`. The full text is copied below.

## Spec (verbatim)

> # 4.5 RunsScreen: footer shows the announced am version and schema (card a9c44f17)
>
> This narrows `docs/superpowers/specs/2026-10-05-align-run-model-design.md`
> (called "the parent" below). It draws on these parts of the parent:
> - Decision 8 (line 172: "Both cancel spellings, both hello schemas").
> - "Both spellings, both schemas" (lines 286-304), in particular the `RunStore`
>   bullet (lines 301-302: `amSchema` is 0 until a hello arrives, `amVersion`
>   from that line, both reset when the watch stops or the project switches) and
>   the `RunsScreen` footer bullet (lines 303-304: `am <version> · schema N ·
>   watching` while a hello is known, the S1 mockup, else `am · watching` /
>   `am · not watching`).
> - "Not changed" (line 314: screen layouts do not change).
> - Work breakdown item 4 (lines 329-330) names "the footer" as part of this
>   story; item 5 (line 331) owns the docs.
>
> The S1 mockup the parent cites is
> `docs/superpowers/specs/2026-10-03-am-run-monitor-design.md:198`:
> `am 0.1.0 · schema 1 · watching`.
>
> The parent story is 27d8a320. This card is blocked by 4.4 (41301b87), which is
> already on this branch.
>
> ## Starting point
>
> - `core/stores/RunStore.qml:31-32` has `property int amSchema: 0` (0 =
>   unknown) and `property string amVersion: ""` (`""` = unknown). They are set
>   from the current watch's hello and reset to `0` / `""` whenever the watch
>   stops, exits or restarts (card 4.4). `amSchema` is never negative or
>   fractional: it is 0 or an integer of 1 or more.
> - `ui/screens/RunsScreen.qml:139-153` is the footer, a `UI.ThemedText` with
>   `objectName: "runsFooter"`. Its text today is, in order of precedence:
>   1. `app.runs.flashText` when it is not `""`;
>   2. `app.runs.lastError` when `amStatus` is `"error"` and `lastError` is not
>      `""`;
>   3. otherwise the hardcoded `"am · schema 1 · "` followed by `watching` or
>      `not watching` (from `app.runs.watching`), line 151.
>
>   Its `visible` binding (line 144) is
>   `(!amMissing && amStatus !== "schema") || flashText !== ""`.
> - `tests/ui/screens/tst_runs_screen.qml` drives the screen with a fake store
>   (`runsC`, lines 26-62). That fake has no `amSchema` / `amVersion`. Three
>   assertions hardcode the old line: lines 317 and 320
>   (`test_the_footer_says_whether_the_runs_are_watched`) and line 492
>   (`test_a_flash_takes_the_footer_and_then_gives_it_back`).
> - `tests/fixtures/am/watch-hello.json` holds the real am hello: `am: "0.1.0"`,
>   `schema: 1`.
>
> ## Required behaviour
>
> 1. **The watch line (precedence 3) reads the announced hello.** With
>    `v = app.runs.amVersion`, `n = app.runs.amSchema` and `w` = `watching`
>    when `app.runs.watching` is true, else `not watching`:
>
>    | `amSchema` | `amVersion` | footer text |
>    |---|---|---|
>    | `0` | anything | `am · <w>` |
>    | `n ≥ 1` | non-empty `v` | `am <v> · schema <n> · <w>` |
>    | `n ≥ 1` | `""` | `am · schema <n> · <w>` |
>
>    Examples: `am 0.1.0 · schema 1 · watching`, `am 0.2.0 · schema 2 · not
>    watching`, `am · watching`, `am · not watching`, `am · schema 2 · watching`.
>
>    The separator is ` · ` (space, U+00B7 middle dot, space), exactly as today.
>    `<n>` is printed as a plain integer (`2`, never `2.0`).
>
>    The third row is a decision this spec makes: the parent (lines 303-304) and
>    the card describe the known-hello line only as `am <version> · schema N`.
>    Read literally, an empty version would give `am  · schema N` with two
>    spaces. Instead the version and its space are left out. The store can reach
>    this row: 4.4 sets `amVersion` to `""` when the hello's `am` is not a string,
>    while still taking a valid `schema`.
>
>    The `watching` vs `amSchema` combinations are independent: the footer
>    prints what the store says and does not cross-check them (for example
>    `amSchema 1` with `watching false` reads `am 0.1.0 · schema 1 · not
>    watching`).
>
> 2. **The text follows the store live.** When `amSchema`, `amVersion` or
>    `watching` change while the screen is shown, the footer text changes with
>    them, with no reload of the screen. This holds both ways: a hello arriving
>    (0 → n) and a reset (n → 0).
>
> 3. **Precedence unchanged.** A non-empty `flashText` still wins over
>    everything. With no flash, `amStatus === "error"` with a non-empty
>    `lastError` still shows `lastError`. Only when neither applies does the
>    watch line of rule 1 show. When a flash or the error clears, the footer
>    falls back to the watch line of rule 1 for the current
>    `amSchema` / `amVersion` / `watching`.
>
> 4. **Visibility unchanged.** The `visible` binding stays exactly as it is
>    (line 144): hidden when am is missing or the schema banner shows, unless a
>    flash is showing. `amSchema` / `amVersion` have no effect on visibility.
>
> 5. **Nothing else on the screen changes.** No other object, layout, binding,
>    objectName or keyboard behaviour changes (parent line 314). The screen still
>    reads only `app.runs` and does not import `core/stores`
>    (`docs/architecture.md:169`).
>
> 6. **Comments state the contract only.** The comment above the footer
>    (lines 139-140) may say the watch line names the announced am version and
>    schema when known. No mention of am's migration, cards, plans or history.
>
> ## Error paths
>
> - `amSchema` 0 with a non-empty `amVersion` (the store never does this, since
>   both are written from the same line and reset together, but the footer must
>   not depend on that): shows `am · <w>`. The version is shown only alongside a
>   known schema.
> - The screen must produce no QML warning (`TypeError`, `ReferenceError`,
>   `Unable to assign`, `non-existent`) for any row of rule 1. `tests/run.sh`
>   fails on those.
> - An error or flash line is never prefixed or suffixed with the am version or
>   schema.
>
> ## Tests
>
> All new and changed tests are in `tests/ui/screens/tst_runs_screen.qml`.
> **Tier: QML UI screen test** (qmltestrunner via `tests/run.sh`), because the
> contract is the text of one bound `ThemedText` that depends on a store's
> properties. A screen test with a fake store pins exactly that, with no am
> process, no real `RunStore` and no panel. The store side (how `amSchema` /
> `amVersion` get their values and when they reset) is already pinned by 4.4 in
> `tests/core/stores/tst_run_store.qml` and is not re-tested here.
>
> Fake store change: add `property int amSchema: 0` and
> `property string amVersion: ""` to `runsC`, so it matches the real store's
> defaults.
>
> Changed tests (old literal → new expected text under the fake's defaults,
> `amSchema 0`):
> - `test_the_footer_says_whether_the_runs_are_watched`: `am · watching`, then
>   `am · not watching` after `watching = false`, and still visible.
> - `test_a_flash_takes_the_footer_and_then_gives_it_back` (line 492): after the
>   flash clears, `am · watching`. The rest of that test is unchanged.
>
> New tests:
> 1. `test_the_footer_names_am_and_schema_1_from_the_hello`: set
>    `amVersion "0.1.0"` and `amSchema 1` (the real fixture's values); expect
>    `am 0.1.0 · schema 1 · watching`; set `watching = false`; expect
>    `am 0.1.0 · schema 1 · not watching`.
> 2. `test_the_footer_names_schema_2_from_the_hello`: `amVersion "0.2.0"`,
>    `amSchema 2`; expect `am 0.2.0 · schema 2 · watching`.
> 3. `test_the_footer_without_a_hello_names_no_schema`: defaults give
>    `am · watching`. Then set `amSchema 1` and `amVersion "0.1.0"` and check
>    the full line, then set `amSchema 0` and `amVersion ""` (a reset) and check
>    it goes back to `am · watching` (rule 2, both directions).
> 4. `test_the_footer_leaves_out_an_unknown_version`: `amSchema 2`,
>    `amVersion ""` → `am · schema 2 · watching` (rule 1, third row).
> 5. `test_the_footer_shows_no_version_without_a_schema`: `amSchema 0`,
>    `amVersion "0.1.0"` → `am · watching` (error path 1).
> 6. `test_flash_and_error_still_win_over_the_announced_hello`: with
>    `amSchema 2`, `amVersion "0.2.0"`: a flash shows the flash; clearing it
>    shows `am 0.2.0 · schema 2 · watching`; `amStatus "error"` with
>    `lastError "AmFailed: boom"` shows `AmFailed: boom`; a flash over the error
>    shows the flash; clearing the flash shows the error again; `amStatus "ok"`
>    shows the watch line again (rule 3).
> 7. `test_the_hello_does_not_unhide_the_footer`: `amSchema 1`,
>    `amVersion "0.1.0"`; with `amStatus "missing"` the footer is not visible;
>    with `amStatus "schema"` it is not visible (rule 4).
>
> Existing tests that must pass unchanged: everything else in
> `tst_runs_screen.qml` (including the missing-am and schema-banner tests at
> lines ~294-345), `tests/architecture` (no new component, no glyph), and the
> whole `bash tests/run.sh`.
>
> ## Files
>
> - Modify: `ui/screens/RunsScreen.qml` (footer `text` binding, line 151; the
>   comment at lines 139-140 only if it needs the contract wording).
> - Modify: `tests/ui/screens/tst_runs_screen.qml` (fake store properties;
>   the three literals; the new tests above).
>
> No other file changes. One task with its own test cycle is enough: the
> deliverable is one binding.
>
> ## Verification
>
> `bash tests/run.sh` green.
>
> ## Out of scope
>
> - `RunStore`'s `amSchema` / `amVersion` (how they are read and reset): card 4.4,
>   done.
> - `runs.js`, `runs-snapshot.py`, `runs-watch.py`: cards 4.1-4.3, done.
> - `README.md:154` and `docs/architecture.md:169`, which still quote
>   `am · schema 1 · watching`, and `README.md:258` ("am must speak journal
>   schema 1"): docs are work breakdown item 5 (parent line 331), "written from
>   the implementation". This card does not edit them.
> - The schema-mismatch banner, the stale banner, the warning line, Run detail,
>   the sidebar and any other surface: no change.
> - Showing the version or schema anywhere other than the Runs footer.

## Global Constraints

- The separator is ` · ` (space, U+00B7 middle dot, space), exactly as today.
- `<n>` is printed as a plain integer (`2`, never `2.0`).
- Rule 1 table: `amSchema 0` → `am · <w>`; `n ≥ 1` with non-empty `v` → `am <v> · schema <n> · <w>`; `n ≥ 1` with `""` → `am · schema <n> · <w>`; `<w>` is `watching` or `not watching`.
- Precedence unchanged: non-empty `flashText`, then `lastError` when `amStatus === "error"` and `lastError !== ""`, then the watch line.
- The `visible` binding stays exactly `(!screen.amMissing && screen.app.runs.amStatus !== "schema") || screen.app.runs.flashText !== ""`.
- No other object, layout, binding, objectName or keyboard behaviour changes; the screen reads only `app.runs` and does not import `core/stores` (`docs/architecture.md:169`).
- Comments state the contract only: no mention of am's migration, cards, plans or history.
- No QML warning (`TypeError`, `ReferenceError`, `Unable to assign`, `non-existent`) for any row of rule 1; `tests/run.sh` fails on those.
- No other file changes: only `ui/screens/RunsScreen.qml` and `tests/ui/screens/tst_runs_screen.qml`. `README.md` and `docs/architecture.md` are NOT edited (docs card, item 5).

## Review Focus

1. A hello that arrives while the error line shows: the footer keeps showing `lastError`; when `amStatus` goes back to `"ok"` it shows the new hello line, not the old `am · watching`. Pinned by `test_a_hello_that_arrives_under_the_error_line_shows_once_the_error_clears` (Task 1).
2. A hello forgotten (reset to `0` / `""`) while a flash covers the footer, with `watching` flipping to false: when the flash clears the footer shows `am · not watching`, never the stale version. Pinned by `test_a_hello_forgotten_under_a_flash_is_not_shown_after_it` (Task 1).
3. Leaving the schema banner (`amStatus "schema"` → `"ok"`) with a hello known: the footer comes back visible with `am <v> · schema <n> · watching`. Pinned by `test_the_footer_comes_back_from_the_schema_banner_with_the_hello` (Task 1).
4. A schema number with more than one digit (`10`) prints as `schema 10`, not `schema 1` or `10.0`. Pinned by `test_a_two_digit_schema_prints_as_a_plain_integer` (Task 1).
5. A version string that is not plain `x.y.z` (`0.2.0-rc.1`) prints verbatim. Pinned by `test_a_pre_release_version_prints_verbatim` (Task 1).

---

## File Structure

- `ui/screens/RunsScreen.qml` — the Runs screen. Only the `runsFooter` `UI.ThemedText` changes: its `text` binding's last branch (currently line 151) and the comment above it (lines 139-140).
- `tests/ui/screens/tst_runs_screen.qml` — the screen test with the fake store `runsC`. Gains `amSchema` / `amVersion` on the fake, three literals updated, a new section of tests.

One task: the deliverable is one binding, and its tests are one test cycle.

---

### Task 1: The Runs footer's watch line reads the announced hello

**Files:**
- Modify: `ui/screens/RunsScreen.qml:139-153` (the `runsFooter` comment and `text` binding)
- Test: `tests/ui/screens/tst_runs_screen.qml` (fake store at lines 26-62; literals at lines 317, 320, 492; new section before line 366 `// ---- robustness and visibility`)

**Interfaces:**
- Consumes: `app.runs.amSchema` (`int`, `0` = no hello known, otherwise an integer ≥ 1) and `app.runs.amVersion` (`string`, `""` = unknown), both already on `core/stores/RunStore.qml:31-32` (card 4.4). Also the existing `app.runs.watching`, `flashText`, `amStatus`, `lastError`.
- Produces: the `runsFooter` text described by the Global Constraints. Nothing else depends on it.

- [ ] **Step 1: Give the fake store the two hello properties**

In `tests/ui/screens/tst_runs_screen.qml`, inside `Component { id: runsC; QtObject { id: rs ... } }`, find:

```qml
      property string watchSchemaError: ""
      property string flashText: ""
```

and replace it with:

```qml
      property string watchSchemaError: ""
      property string flashText: ""
      // The current watch's hello, with the real store's defaults (0 / "" =
      // no hello known).
      property int amSchema: 0
      property string amVersion: ""
```

- [ ] **Step 2: Update the existing footer literals to the no-hello line**

In the same file, find:

```qml
  function test_the_footer_says_whether_the_runs_are_watched() {
    var s = make(sample()); if (!s) return
    var footer = H.find(s.screen, "runsFooter")
    compare(footer.text, "am · schema 1 · watching")
    compare(footer.visible, true)
    s.runs.watching = false
    compare(footer.text, "am · schema 1 · not watching")
  }
```

and replace it with:

```qml
  function test_the_footer_says_whether_the_runs_are_watched() {
    var s = make(sample()); if (!s) return
    var footer = H.find(s.screen, "runsFooter")
    compare(footer.text, "am · watching")
    compare(footer.visible, true)
    s.runs.watching = false
    compare(footer.text, "am · not watching")
    compare(footer.visible, true)
  }
```

Then, in `test_a_flash_takes_the_footer_and_then_gives_it_back`, find:

```qml
    s.runs.flashText = ""
    compare(footer.text, "am · schema 1 · watching")
```

and replace it with:

```qml
    s.runs.flashText = ""
    compare(footer.text, "am · watching")
```

Leave the rest of that test unchanged.

- [ ] **Step 3: Add the tests for the announced hello**

In the same file, find the line:

```qml
  // ---- robustness and visibility
```

and replace it with:

```qml
  // ---- the announced hello in the footer

  function test_the_footer_names_am_and_schema_1_from_the_hello() {
    var s = make(sample()); if (!s) return
    var footer = H.find(s.screen, "runsFooter")
    s.runs.amVersion = "0.1.0"
    s.runs.amSchema = 1
    compare(footer.text, "am 0.1.0 · schema 1 · watching")
    s.runs.watching = false
    compare(footer.text, "am 0.1.0 · schema 1 · not watching")
  }

  function test_the_footer_names_schema_2_from_the_hello() {
    var s = make(sample()); if (!s) return
    var footer = H.find(s.screen, "runsFooter")
    s.runs.amVersion = "0.2.0"
    s.runs.amSchema = 2
    compare(footer.text, "am 0.2.0 · schema 2 · watching")
  }

  function test_the_footer_without_a_hello_names_no_schema() {
    var s = make(sample()); if (!s) return
    var footer = H.find(s.screen, "runsFooter")
    compare(footer.text, "am · watching")
    s.runs.amSchema = 1
    s.runs.amVersion = "0.1.0"
    compare(footer.text, "am 0.1.0 · schema 1 · watching", "a hello arrives")
    s.runs.amSchema = 0
    s.runs.amVersion = ""
    compare(footer.text, "am · watching", "the hello is forgotten")
  }

  function test_the_footer_leaves_out_an_unknown_version() {
    var s = make(sample()); if (!s) return
    var footer = H.find(s.screen, "runsFooter")
    s.runs.amSchema = 2
    s.runs.amVersion = ""
    compare(footer.text, "am · schema 2 · watching")
  }

  function test_the_footer_shows_no_version_without_a_schema() {
    var s = make(sample()); if (!s) return
    var footer = H.find(s.screen, "runsFooter")
    s.runs.amVersion = "0.1.0"
    compare(footer.text, "am · watching")
    s.runs.watching = false
    compare(footer.text, "am · not watching")
  }

  function test_flash_and_error_still_win_over_the_announced_hello() {
    var s = make(sample()); if (!s) return
    var footer = H.find(s.screen, "runsFooter")
    s.runs.amSchema = 2
    s.runs.amVersion = "0.2.0"
    s.runs.flashText = "The run has finished"
    compare(footer.text, "The run has finished", "the flash alone, with no am prefix")
    s.runs.flashText = ""
    compare(footer.text, "am 0.2.0 · schema 2 · watching")
    s.runs.amStatus = "error"
    s.runs.lastError = "AmFailed: boom"
    compare(footer.text, "AmFailed: boom", "the error alone, with no am prefix")
    s.runs.flashText = "The run is still running"
    compare(footer.text, "The run is still running", "the flash wins over the error line")
    s.runs.flashText = ""
    compare(footer.text, "AmFailed: boom")
    s.runs.amStatus = "ok"
    compare(footer.text, "am 0.2.0 · schema 2 · watching")
  }

  function test_the_hello_does_not_unhide_the_footer() {
    var s = make(sample()); if (!s) return
    var footer = H.find(s.screen, "runsFooter")
    s.runs.amSchema = 1
    s.runs.amVersion = "0.1.0"
    compare(footer.visible, true)
    s.runs.amStatus = "missing"
    wait(20)
    compare(footer.visible, false, "am is missing")
    s.runs.amStatus = "schema"
    wait(20)
    compare(footer.visible, false, "the schema banner shows")
  }

  // Review Focus 1.
  function test_a_hello_that_arrives_under_the_error_line_shows_once_the_error_clears() {
    var s = make(sample()); if (!s) return
    var footer = H.find(s.screen, "runsFooter")
    s.runs.amStatus = "error"
    s.runs.lastError = "AmFailed: boom"
    s.runs.amSchema = 1
    s.runs.amVersion = "0.1.0"
    compare(footer.text, "AmFailed: boom")
    s.runs.amStatus = "ok"
    compare(footer.text, "am 0.1.0 · schema 1 · watching")
  }

  // Review Focus 2.
  function test_a_hello_forgotten_under_a_flash_is_not_shown_after_it() {
    var s = make(sample()); if (!s) return
    var footer = H.find(s.screen, "runsFooter")
    s.runs.amSchema = 2
    s.runs.amVersion = "0.2.0"
    s.runs.flashText = "The run has finished"
    s.runs.amSchema = 0
    s.runs.amVersion = ""
    s.runs.watching = false
    compare(footer.text, "The run has finished")
    s.runs.flashText = ""
    compare(footer.text, "am · not watching")
  }

  // Review Focus 3.
  function test_the_footer_comes_back_from_the_schema_banner_with_the_hello() {
    var s = make(sample()); if (!s) return
    var footer = H.find(s.screen, "runsFooter")
    s.runs.amSchema = 2
    s.runs.amVersion = "0.2.0"
    s.runs.amStatus = "schema"
    wait(20)
    compare(footer.visible, false)
    s.runs.amStatus = "ok"
    wait(20)
    compare(footer.visible, true)
    compare(footer.text, "am 0.2.0 · schema 2 · watching")
  }

  // Review Focus 4.
  function test_a_two_digit_schema_prints_as_a_plain_integer() {
    var s = make(sample()); if (!s) return
    var footer = H.find(s.screen, "runsFooter")
    s.runs.amSchema = 10
    s.runs.amVersion = "1.0.0"
    compare(footer.text, "am 1.0.0 · schema 10 · watching")
  }

  // Review Focus 5.
  function test_a_pre_release_version_prints_verbatim() {
    var s = make(sample()); if (!s) return
    var footer = H.find(s.screen, "runsFooter")
    s.runs.amSchema = 2
    s.runs.amVersion = "0.2.0-rc.1"
    compare(footer.text, "am 0.2.0-rc.1 · schema 2 · watching")
  }

  // ---- robustness and visibility
```

- [ ] **Step 4: Run the screen tests to see them fail**

Run: `bash tests/run.sh tst_runs_screen`

Expected: pytest passes first (it always runs), then `== tests/ui/screens/tst_runs_screen.qml` prints `FAIL!` lines, because the footer still prints the hardcoded `am · schema 1 · `. These tests must FAIL:
`test_the_footer_says_whether_the_runs_are_watched` (actual `am · schema 1 · watching`),
`test_a_flash_takes_the_footer_and_then_gives_it_back`,
`test_the_footer_names_am_and_schema_1_from_the_hello`,
`test_the_footer_names_schema_2_from_the_hello`,
`test_the_footer_without_a_hello_names_no_schema`,
`test_the_footer_leaves_out_an_unknown_version`,
`test_the_footer_shows_no_version_without_a_schema`,
`test_flash_and_error_still_win_over_the_announced_hello`,
`test_a_hello_that_arrives_under_the_error_line_shows_once_the_error_clears`,
`test_a_hello_forgotten_under_a_flash_is_not_shown_after_it`,
`test_the_footer_comes_back_from_the_schema_banner_with_the_hello`,
`test_a_two_digit_schema_prints_as_a_plain_integer`,
`test_a_pre_release_version_prints_verbatim`.

`test_the_hello_does_not_unhide_the_footer` already PASSES (visibility does not change in this task; the test guards it). No `TypeError` / `ReferenceError` / `non-existent` / `Unable to assign` line may appear; if one does, the fake store properties from Step 1 are wrong.

- [ ] **Step 5: Change the footer binding**

In `ui/screens/RunsScreen.qml`, find:

```qml
  // The watch line, or why the last run key was refused while that flash
  // lasts; a flash shows even where the footer is otherwise hidden.
  UI.ThemedText {
    objectName: "runsFooter"
    variant: "caption"
    theme: screen.theme
    width: parent.width
    visible: (!screen.amMissing && screen.app.runs.amStatus !== "schema") || screen.app.runs.flashText !== ""
    text: screen.app.runs.flashText !== ""
      ? screen.app.runs.flashText
      : screen.app.runs.amStatus === "error" && screen.app.runs.lastError !== ""
        ? screen.app.runs.lastError
        : "am · schema 1 · " + (screen.app.runs.watching ? "watching" : "not watching")
    wrapMode: Text.WordWrap
  }
```

and replace it with:

```qml
  // The watch line, naming the am version and journal schema the watch
  // announced once they are known, or why the last run key was refused while
  // that flash lasts; a flash shows even where the footer is otherwise hidden.
  UI.ThemedText {
    objectName: "runsFooter"
    variant: "caption"
    theme: screen.theme
    width: parent.width
    visible: (!screen.amMissing && screen.app.runs.amStatus !== "schema") || screen.app.runs.flashText !== ""
    text: screen.app.runs.flashText !== ""
      ? screen.app.runs.flashText
      : screen.app.runs.amStatus === "error" && screen.app.runs.lastError !== ""
        ? screen.app.runs.lastError
        : "am" +
          (screen.app.runs.amSchema > 0 && screen.app.runs.amVersion !== "" ? " " + screen.app.runs.amVersion : "") +
          (screen.app.runs.amSchema > 0 ? " · schema " + screen.app.runs.amSchema : "") +
          " · " + (screen.app.runs.watching ? "watching" : "not watching")
    wrapMode: Text.WordWrap
  }
```

Notes for the implementer:
- `?:` binds looser than `+`, so the whole `"am" + ... + ...` sum is the last branch; the flash and error branches are untouched and never get an am prefix.
- `amSchema` is a QML `int`, so `" · schema " + amSchema` prints `2`, never `2.0`.
- The version is only printed when `amSchema > 0` (error path: `amSchema 0` with a non-empty `amVersion` shows `am · <w>`).
- The `visible` line is copied unchanged. Do not touch anything else in the file, and do not import `core/stores`.

- [ ] **Step 6: Run the screen tests to see them pass**

Run: `bash tests/run.sh tst_runs_screen`

Expected: pytest passes; `== tests/ui/screens/tst_runs_screen.qml` prints a `Totals:` line with `0 failed` and no `FAIL!` line; no `TypeError` / `ReferenceError` / `non-existent` / `Unable to assign` line; exit status 0.

- [ ] **Step 7: Run the whole suite**

Run: `bash tests/run.sh`

Expected: exit status 0; every `Totals:` line shows `0 failed` (including `tests/architecture` and `tests/core/stores/tst_run_store.qml`), and no QML warning line is printed.

- [ ] **Step 8: Check the diff touches only the two files**

Run: `git status --short && git diff --stat`

Expected: only `ui/screens/RunsScreen.qml` and `tests/ui/screens/tst_runs_screen.qml` are modified (plus the untracked spec/plan docs, which are committed separately by the workflow). `README.md` and `docs/architecture.md` are unchanged.

- [ ] **Step 9: Commit**

```bash
git add ui/screens/RunsScreen.qml tests/ui/screens/tst_runs_screen.qml
git commit -m "feat(runs): the Runs footer names the am version and schema the watch announced

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```
<!-- task-pipeline: validated -->
