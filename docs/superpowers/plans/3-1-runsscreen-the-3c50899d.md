# 3.1 RunsScreen: the Desktop notifications switch (card 3c50899d)

Narrowed from `docs/superpowers/specs/2026-10-05-alerts-panel-closed-design.md` (below "the
parent"): Behaviour, "The panel" (lines 129-130: "The Runs screen's switch reads `Desktop
notifications` with the caption `From the background, panel open or closed`"); Architecture,
the `RunsScreen.qml` bullet (line 162: "the switch label and caption"); Testing, the
`tst_runs_screen.qml` item (line 209: "the switch label and caption"). Parent story 2bf08513.

This card changes **what the Runs screen's notify switch says**, and nothing else about it.

## Starting point

- `ui/screens/RunsScreen.qml` l.313-333: a `Row` (`objectName: "runsNotifyRow"`,
  `spacing: Style.space(8)`) holding
  - `ToggleSwitch` `runsNotifyToggle` (l.319-324): `checked:
    screen.app.runControl.notifyOnEscalation`, `onToggled:
    screen.app.runControl.setNotifyOnEscalation(!screen.app.runControl.notifyOnEscalation)`;
  - `UI.ThemedText` `runsNotifyLabel` (l.326-332): `variant: "caption"`, `theme:
    screen.theme`, `text: "Notify on escalation"`.
  The comment above it (l.313-314) reads "The global Notify on escalation setting: a desktop
  notification for every run toast. Shown with or without a project, and while am is missing."
  The row is not gated by project or `amStatus`; it sits directly above `runsFooter`.
- `ui/components/ThemedText.qml`: variants `body | small | caption | heading | dim`;
  `caption` and `dim` both paint `palette.dim`; `caption` uses `captionSize`, `dim` uses
  `bodySize`.
- Tests: `tests/ui/screens/tst_runs_screen.qml`, section "the Notify on escalation switch
  (S2 4.4)" (l.997), `test_the_notify_switch_reads_and_asks_the_store` (l.1000-1020) asserts
  the label text at l.1006; `test_the_screen_is_hidden_outside_its_section` (l.866-876)
  asserts the row visible with no project. `tests/ui/tst_runs_flow.qml` l.815-824 (F5) toggles
  the switch with no project through the real store. `H.find(root, objectName)` is the lookup
  helper.
- Runner: `bash tests/run.sh [path-substring]` (pytest incl. `tests/architecture`, then every
  `tst_*.qml` offscreen; it also fails on `TypeError` / `ReferenceError` / `non-existent` /
  `Unable to assign` lines).

## Constraints

- Layering per `docs/architecture.md`; `tests/architecture` must pass (no duplicated
  components, icon glyph rules). No new component and no glyph is introduced (card).
- Binding, setter and visibility are unchanged (card: "Same binding and setter as today; shown
  with and without a project and while am is missing, as today").
- The screen reads `screen.app` / props only; it imports no store (architecture layering).
- Comments state the contract only, no narrative (card).
- TDD: the new assertions are written and seen failing before the screen changes (card).
- Gate: `bash tests/run.sh` green.

## Behaviour

1. The switch's label (`runsNotifyLabel`) reads exactly `Desktop notifications`.
2. A caption (`objectName: "runsNotifyCaption"`) reads exactly
   `From the background, panel open or closed`. It is a `UI.ThemedText` with `theme:
   screen.theme` and `variant: "caption"` (the dim colour, caption size), shown under the
   label; the label and the caption sit together to the right of the toggle, the pair
   vertically centred on it.
3. The label stays `variant: "caption"` as today (its look is unchanged; only its text is).
4. The caption is visible whenever the row is: with a project, with no project, and with
   `app.runs.amStatus === "missing"`. It has no binding of its own to project, am state or
   the switch value; its text does not change with the switch.
5. Toggle behaviour is unchanged: `checked` follows `app.runControl.notifyOnEscalation`;
   `toggled()` calls `setNotifyOnEscalation` once with the flipped value and does not flip the
   switch itself.
6. The row stays above `runsFooter` (its `y` is less than the footer's).
7. The comment above the row states the new contract: the global desktop-notifications
   setting, raised by the background service whether the panel is open or closed; shown with
   or without a project and while am is missing.

## Out of scope

- `core/stores/RunControlStore.qml` and its flash text `Notify on escalation could not be
  saved` (and the `tst_run_control_store.qml` assertions on it): not the screen's label.
- The property/method names `notifyOnEscalation` / `setNotifyOnEscalation` and the objectNames
  `runsNotifyRow` / `runsNotifyToggle` / `runsNotifyLabel`: kept.
- `README.md` l.154 and `docs/architecture.md` l.92 and l.168, which still name "Notify on
  escalation": the docs card of the parent story owns them.
- `RunAlertsService`, `RunAlertsStore`, `runs-alerts.py`, `notify.py`: sibling cards.

## Tests

All in `tests/ui/screens/tst_runs_screen.qml`, tier: **QML screen test** (qmltestrunner,
offscreen, stubbed `app`) — the behaviour is the text and visibility of items the screen
draws from props, which is exactly what this tier observes; no store or backend logic is
involved, so neither a store test nor a pytest applies.

1. `test_the_notify_switch_reads_and_asks_the_store` (existing, l.1000): the label assertion
   becomes `compare(H.find(s.screen, "runsNotifyLabel").text, "Desktop notifications")`; add
   `verify` the caption exists and `compare(caption.text, "From the background, panel open or
   closed")` and `compare(caption.visible, true)`. Existing toggle and footer-order assertions
   stay. After `s.runs.amStatus = "missing"`, also assert the caption still visible.
   Fails first on the label text and on the missing caption.
2. `test_the_screen_is_hidden_outside_its_section` (existing, l.866): with no project, also
   assert `H.find(s.screen, "runsNotifyCaption").visible === true` ("and its caption").
3. New `test_the_notify_caption_sits_under_the_label`: the caption's mapped `y` is greater than
   the label's mapped `y` (both mapped into `s.screen`), and both lie to the right of the
   toggle (mapped `x` greater than the toggle's mapped `x` + width). Pins behaviour 2's layout
   without pinning pixel values. Also asserts the caption text does not change when
   `s.control.notifyOnEscalation` flips true then false.

`tests/ui/tst_runs_flow.qml` F5 is left as is; it must keep passing (it pins the binding and
setter through the real store with no project).

## Review focus

- A long caption at a narrow panel width: the row must not overlap the footer; the caption
  is caption-size single line, and the footer-order assertion (behaviour 6) catches overlap of
  the row's box.
- The caption resolving no theme during teardown: `ThemedText` already guards a null theme;
  the run must print no `TypeError`/`ReferenceError` (the runner fails on them).

---

# 3.1 RunsScreen: the Desktop notifications switch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Runs screen's notify switch reads `Desktop notifications` with the caption `From the background, panel open or closed`, with binding, setter and visibility unchanged.

**Architecture:** One QML screen edit in `ui/screens/RunsScreen.qml`: the `runsNotifyRow` `Row` keeps its `ToggleSwitch` and replaces the lone label with a `Column` (vertically centred on the toggle) holding the relabelled `runsNotifyLabel` and a new `runsNotifyCaption`. Tests are QML screen tests in `tests/ui/screens/tst_runs_screen.qml`, written and seen failing first.

**Tech Stack:** QML (Qt 6 / Quickshell), qmltestrunner offscreen via `bash tests/run.sh`, pytest for `tests/architecture`.

**Spec:** `docs/superpowers/specs/3-1-runsscreen-the-3c50899d.md` (prepended above).

## Global Constraints

- Layering per `docs/architecture.md`; `tests/architecture` must pass. No new component, no glyph.
- Binding, setter and visibility are unchanged: `checked: screen.app.runControl.notifyOnEscalation`, `onToggled: screen.app.runControl.setNotifyOnEscalation(!screen.app.runControl.notifyOnEscalation)`; the row is not gated by project or `amStatus`.
- The screen reads `screen.app` / props only; it imports no store.
- objectNames `runsNotifyRow` / `runsNotifyToggle` / `runsNotifyLabel` are kept; the new caption is `runsNotifyCaption`.
- Label text exactly `Desktop notifications`; caption text exactly `From the background, panel open or closed`.
- Comments state the contract only, no narrative.
- TDD: the new assertions are seen failing before the screen changes.
- Gate: `bash tests/run.sh` green (it also fails on `TypeError` / `ReferenceError` / `non-existent` / `Unable to assign` / `anchors on an item` / `is not a function` lines).
- Out of scope: `RunControlStore.qml` and its flash text, `README.md`, `docs/architecture.md`, `tst_runs_flow.qml` (left as is, must keep passing).

## Review Focus

1. **The caption with no project and while am is missing** — a person with no registered project, or without `am` installed, still sees the switch and its caption. Pinned in Task 1 Step 1 (`test_the_screen_is_hidden_outside_its_section` and the `amStatus = "missing"` tail of `test_the_notify_switch_reads_and_asks_the_store`).
2. **The caption's text flipping with the switch** — the caption describes the setting, not its state; it must read the same on and off. Pinned in Task 1 Step 1 (`test_the_notify_caption_sits_under_the_label`).
3. **The label and caption sitting beside, not over, the toggle** — a `Column` without vertical centring, or children placed in the `Row` directly, would put the caption beside the label rather than under it. Pinned in Task 1 Step 1 (caption `y` > label `y`, both `x` right of the toggle).
4. **The row overlapping the footer once it grows a second line** — the row is taller now; it must stay above `runsFooter`. Pinned by the existing `row.y < footer.y` assertion, kept in Step 1.
5. **Anchor misuse inside a positioner** — `anchors.verticalCenter` on a child of a `Column` (rather than of the `Row`) makes Qt print an "anchors on an item … managed by a layout/positioner" warning, which `tests/run.sh` fails on. Only the `Column` itself (a child of the `Row`) carries `anchors.verticalCenter`; the two texts inside it carry none. Caught by the runner's warning grep in Step 4.

---

### Task 1: The Desktop notifications label and its caption

**Files:**
- Modify: `tests/ui/screens/tst_runs_screen.qml:866-876` (`test_the_screen_is_hidden_outside_its_section`)
- Modify: `tests/ui/screens/tst_runs_screen.qml:997-1020` (section header and `test_the_notify_switch_reads_and_asks_the_store`, plus a new test after it)
- Modify: `ui/screens/RunsScreen.qml:313-333` (the `runsNotifyRow` and its comment)

**Interfaces:**
- Consumes: the test file's existing `make(list)` (returns `{ app, runs, control, nav, navi, screen }`), `sample()`, `H.find(root, objectName)`; the stub `control` with `notifyOnEscalation` (bool) and `notifyCalls` (array) and `setNotifyOnEscalation(on)`.
- Produces: a `UI.ThemedText` with `objectName: "runsNotifyCaption"` inside `runsNotifyRow`; `runsNotifyLabel.text === "Desktop notifications"`. Nothing later depends on it in this plan.

- [ ] **Step 1: Write the failing tests**

In `tests/ui/screens/tst_runs_screen.qml`, replace `test_the_screen_is_hidden_outside_its_section` (l.866-876) with:

```qml
  function test_the_screen_is_hidden_outside_its_section() {
    var s = make(sample()); if (!s) return
    compare(s.screen.visible, true)
    s.nav.viewMode = "run"
    compare(s.screen.visible, false)
    s.nav.viewMode = "runs"
    s.app.projects = { selectedProject: null }
    compare(s.screen.visible, true, "no project: the Runs list still shows")
    compare(H.find(s.screen, "runsNotifyRow").visible, true, "and so does the notify switch")
    compare(H.find(s.screen, "runsNotifyCaption").visible, true, "and its caption")
  }
```

Then replace the section from the header `// ---- the Notify on escalation switch (S2 4.4)` (l.997) through the end of `test_the_notify_switch_reads_and_asks_the_store` (l.1020) with:

```qml
  // ---- the Desktop notifications switch (S2 4.4, alerts 3.1)

  // 25
  function test_the_notify_switch_reads_and_asks_the_store() {
    var s = make(sample()); if (!s) return
    var row = H.find(s.screen, "runsNotifyRow")
    var toggle = H.find(s.screen, "runsNotifyToggle")
    var caption = H.find(s.screen, "runsNotifyCaption")
    verify(row, "the switch row")
    verify(toggle, "the switch")
    verify(caption, "the switch's caption")
    compare(H.find(s.screen, "runsNotifyLabel").text, "Desktop notifications")
    compare(caption.text, "From the background, panel open or closed")
    compare(caption.visible, true)
    compare(toggle.checked, false)
    s.control.notifyOnEscalation = true
    compare(toggle.checked, true)
    s.control.notifyOnEscalation = false
    compare(toggle.checked, false)
    toggle.toggled()
    compare(s.control.notifyCalls.join(","), "true", "asked once, for the flipped value")
    compare(toggle.checked, false, "the store decides; this stub did not flip it")
    compare(row.visible, true)
    verify(row.y < H.find(s.screen, "runsFooter").y, "above the footer")
    s.runs.amStatus = "missing"
    wait(20)
    compare(row.visible, true, "the setting is the project's, not am's")
    compare(caption.visible, true, "and so is its caption")
  }

  // 3.1
  function test_the_notify_caption_sits_under_the_label() {
    var s = make(sample()); if (!s) return
    var toggle = H.find(s.screen, "runsNotifyToggle")
    var label = H.find(s.screen, "runsNotifyLabel")
    var caption = H.find(s.screen, "runsNotifyCaption")
    verify(label, "the switch's label")
    verify(caption, "the switch's caption")
    var t = toggle.mapToItem(s.screen, 0, 0)
    var l = label.mapToItem(s.screen, 0, 0)
    var c = caption.mapToItem(s.screen, 0, 0)
    verify(c.y > l.y, "the caption is under the label")
    verify(l.x > t.x + toggle.width, "the label is right of the toggle")
    verify(c.x > t.x + toggle.width, "the caption is right of the toggle")
    var text = caption.text
    s.control.notifyOnEscalation = true
    compare(caption.text, text, "the caption does not follow the switch on")
    s.control.notifyOnEscalation = false
    compare(caption.text, text, "nor off")
  }
```

- [ ] **Step 2: Run the screen tests to verify they fail**

Run: `timeout 600 bash tests/run.sh tst_runs_screen`
Expected: pytest passes; the `== tests/ui/screens/tst_runs_screen.qml` block prints `FAIL!` lines for `test_the_screen_is_hidden_outside_its_section` (a `TypeError` on `visible` of null, since `runsNotifyCaption` does not exist), `test_the_notify_switch_reads_and_asks_the_store` (`verify` failure: "the switch's caption"), and `test_the_notify_caption_sits_under_the_label` (`verify` failure: "the switch's caption"); exit status non-zero.

- [ ] **Step 3: Implement the label and caption**

In `ui/screens/RunsScreen.qml`, replace l.313-333 (the comment and the whole `runsNotifyRow` `Row`) with:

```qml
  // The global desktop-notifications setting: a desktop notification for
  // every run alert, raised by the background service whether the panel is
  // open or closed. Shown with or without a project, and while am is missing.
  Row {
    objectName: "runsNotifyRow"
    spacing: Style.space(8)

    ToggleSwitch {
      objectName: "runsNotifyToggle"
      anchors.verticalCenter: parent.verticalCenter
      checked: screen.app.runControl.notifyOnEscalation
      onToggled: screen.app.runControl.setNotifyOnEscalation(!screen.app.runControl.notifyOnEscalation)
    }

    // The label over its caption, centred on the toggle.
    Column {
      anchors.verticalCenter: parent.verticalCenter

      UI.ThemedText {
        objectName: "runsNotifyLabel"
        variant: "caption"
        theme: screen.theme
        text: "Desktop notifications"
      }

      UI.ThemedText {
        objectName: "runsNotifyCaption"
        variant: "caption"
        theme: screen.theme
        text: "From the background, panel open or closed"
      }
    }
  }
```

The two texts carry no anchors: a `Column` positions its children, and an anchor on them would make Qt warn (the runner fails on that warning).

- [ ] **Step 4: Run the screen tests to verify they pass**

Run: `timeout 600 bash tests/run.sh tst_runs_screen`
Expected: pytest passes; `tst_runs_screen.qml` prints `Totals: N passed, 0 failed` with no `FAIL!` lines and no `TypeError` / `ReferenceError` / `anchors on an item` lines; exit status 0.

- [ ] **Step 5: Run the full gate**

Run: `timeout 900 bash tests/run.sh`
Expected: pytest (including `tests/architecture`) passes; every `tst_*.qml` prints `0 failed`, in particular `tests/ui/tst_runs_flow.qml` (F5, `test_with_no_project_the_notify_switch_shows_and_toggles`) and `tests/core/stores/tst_run_control_store.qml`; exit status 0.

- [ ] **Step 6: Commit**

```bash
git add ui/screens/RunsScreen.qml tests/ui/screens/tst_runs_screen.qml
git commit -m "feat(runs): the notify switch reads Desktop notifications, captioned From the background, panel open or closed"
```

---

## Self-review against the spec

- Behaviour 1 (label text): Step 3 sets it; Step 1 test 25 asserts it.
- Behaviour 2 (caption objectName, text, variant, theme, under label, right of toggle, centred on it): Step 3; Step 1 test 25 (text) and test 3.1 (layout).
- Behaviour 3 (label stays `caption`): Step 3 keeps `variant: "caption"`.
- Behaviour 4 (caption visible with project, no project, am missing; no binding to switch): Step 1 test 25, `..._hidden_outside_its_section`, test 3.1 (text on/off); Step 3 gives the caption no `visible` binding.
- Behaviour 5 (toggle unchanged): Step 3 keeps `checked` / `onToggled` verbatim; test 25 keeps its assertions; F5 in Step 5.
- Behaviour 6 (row above footer): test 25 keeps `row.y < footer.y`; Step 3 does not move the row.
- Behaviour 7 (comment contract): Step 3's comment.
- Spec tests 1-3: Step 1, as specified.
- No placeholders; objectNames consistent (`runsNotifyRow`, `runsNotifyToggle`, `runsNotifyLabel`, `runsNotifyCaption`) across steps.
- Stub note: in tests `ToggleSwitch` resolves to `tests/stubs/qs/Ui/ToggleSwitch.qml`, an `Item` with zero size, so `t.x + toggle.width` is the toggle's x and the `Row`'s spacing (8) puts the `Column` strictly right of it.
<!-- task-pipeline: validated -->
