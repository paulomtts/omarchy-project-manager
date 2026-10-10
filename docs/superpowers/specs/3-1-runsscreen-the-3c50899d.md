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
