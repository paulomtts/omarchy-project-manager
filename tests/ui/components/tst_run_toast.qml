// tests/ui/components/tst_run_toast.qml
// ui/components/RunToast.qml on its own, with plain toast objects and no
// store: what each card shows, the order of the stack, the two signals, and
// bad entries.
import QtQuick
import QtTest
import "../../helpers/find.js" as H
import "../../../ui/components" as UI
import "../../../ui/components/runGlyphs.js" as RG
import "../../../ui/theme" as T

TestCase {
  id: tc
  name: "RunToast"
  when: windowShown
  visible: true
  width: 400; height: 500

  T.Theme { id: tcTheme; foreground: "#00ff00"; urgent: "#ff0000" }

  Component { id: toastC; UI.RunToast { theme: tcTheme } }
  SignalSpy { id: openSpy; signalName: "openRequested" }
  SignalSpy { id: dismissSpy; signalName: "dismissRequested" }

  // One RunStore toast; `project` is optional (undefined when left out).
  function toast(key, id, title, state, reason, project) {
    return { key: key, id: id, title: title, state: state, reason: reason, project: project,
             expiresMs: Date.now() + 8000 }
  }

  function make(list) {
    var c = createTemporaryObject(toastC, tc, { toasts: list })
    openSpy.target = c
    openSpy.clear()
    dismissSpy.target = c
    dismissSpy.clear()
    wait(20)
    return c
  }

  function part(c, name, i) { return H.find(c, name + i) }

  // Two clicks inside the double-click interval make the second a double-click.
  function tap(item) {
    wait(450)
    mouseClick(item)
  }

  // 16
  function test_no_toasts_no_cards() {
    var c = make([])
    compare(part(c, "runToast", 0), null)
    compare(c.visible, false)
    compare(c.height, 0)
  }

  // 17
  function test_an_escalated_and_a_dead_toast_read_as_the_mock() {
    var c = make([toast(1, "run-a", "M3", "escalated", "tests red after 3 attempts"),
                  toast(2, "run-b", "M4", "dead", "process died"),
                  toast(3, "run-c", "M5", "escalated", "")])
    compare(c.visible, true)
    compare(c.width, 320)
    compare(part(c, "runToastHeading", 0).text, "‼ Run needs you")
    compare(part(c, "runToastHeading", 0).text, RG.glyphOf("escalated") + " Run needs you")
    compare(String(part(c, "runToastHeading", 0).color), String(tcTheme.urgent))
    compare(part(c, "runToastLine", 0).text, "M3 escalated")
    compare(part(c, "runToastReason", 0).text, "tests red after 3 attempts")
    compare(part(c, "runToastReason", 0).visible, true)
    compare(String(part(c, "runToast", 0).border.color), String(tcTheme.urgent))
    compare(part(c, "runToastOpen", 0).text, "Open")
    compare(part(c, "runToastDismiss", 0).text, "Dismiss")
    compare(part(c, "runToastHeading", 1).text, "✖ Run needs you")
    compare(part(c, "runToastLine", 1).text, "M4 died")
    compare(part(c, "runToastReason", 1).text, "process died")
    compare(part(c, "runToastReason", 2).visible, false, "an empty reason hides its line")
  }

  // 18
  function test_three_toasts_stack_oldest_at_the_top() {
    var c = make([toast(1, "run-a", "A", "escalated", "r"), toast(2, "run-b", "B", "escalated", "r"),
                  toast(3, "run-c", "C", "dead", "process died")])
    compare(part(c, "runToastLine", 0).text, "A escalated")
    compare(part(c, "runToastLine", 1).text, "B escalated")
    compare(part(c, "runToastLine", 2).text, "C died")
    compare(part(c, "runToast", 3), null)
    verify(part(c, "runToast", 0).y < part(c, "runToast", 1).y, "oldest at the top")
    verify(part(c, "runToast", 1).y < part(c, "runToast", 2).y, "newest at the bottom")
    c.toasts = [toast(3, "run-c", "C", "dead", "process died")]
    wait(20)
    compare(part(c, "runToastLine", 0).text, "C died", "a new array re-renders")
    compare(part(c, "runToast", 1), null)
  }

  // 19
  function test_open_and_dismiss_emit_the_toasts_key_and_run() {
    var c = make([toast(7, "run-a", "A", "escalated", "r"), toast(9, "run-b", "B", "dead", "process died")])
    tap(part(c, "runToastOpen", 1))
    compare(openSpy.count, 1)
    compare(openSpy.signalArguments[0][0], 9)
    compare(openSpy.signalArguments[0][1], "run-b")
    compare(dismissSpy.count, 0, "Open does not dismiss by itself: the owner does")
    tap(part(c, "runToastDismiss", 0))
    compare(dismissSpy.count, 1)
    compare(dismissSpy.signalArguments[0][0], 7)
    compare(openSpy.count, 1)
  }

  // 20
  function test_bad_entries_render_without_throwing_and_keep_dismiss() {
    var c = make(["oops", toast(4, "run-x", "X", "bogus", "")])
    compare(part(c, "runToastHeading", 0).text, " Run needs you", "no glyph for a non-object")
    compare(part(c, "runToastLine", 0).text, " escalated")
    compare(part(c, "runToastReason", 0).visible, false)
    verify(part(c, "runToastProject", 0), "a non-object entry still has its project line")
    compare(part(c, "runToastProject", 0).visible, false)
    compare(part(c, "runToastProject", 1).visible, false, "an entry with no project")
    compare(part(c, "runToastDismiss", 0).visible, true)
    compare(part(c, "runToastHeading", 1).text, " Run needs you", "a state with no glyph")
    compare(part(c, "runToastLine", 1).text, "X escalated")
    tap(part(c, "runToastDismiss", 0))
    compare(dismissSpy.count, 1)
    compare(dismissSpy.signalArguments[0][0], -1, "an entry with no key dismisses key -1")
    var d = make(null)
    compare(d.visible, false)
    compare(part(d, "runToast", 0), null)
  }

  // 4.5: the project line
  function test_each_toast_shows_its_project_under_the_heading() {
    var c = make([toast(1, "run-a", "M3", "escalated", "r", "alpha"),
                  toast(2, "run-b", "M4", "dead", "process died", "beta")])
    compare(part(c, "runToastProject", 0).text, "alpha")
    compare(part(c, "runToastProject", 1).text, "beta")
    for (var i = 0; i < 2; i++) {
      var project = part(c, "runToastProject", i)
      compare(project.visible, true)
      verify(project.y > part(c, "runToastHeading", i).y, "under the heading")
      verify(project.y < part(c, "runToastLine", i).y, "above the title line")
    }
    compare(part(c, "runToastLine", 0).text, "M3 escalated")
    compare(part(c, "runToastLine", 1).text, "M4 died")
  }

  function test_a_toast_without_a_project_hides_the_project_line() {
    var c = make([toast(1, "run-a", "A", "escalated", "r", ""),
                  toast(2, "run-b", "B", "escalated", "r", 7)])
    compare(part(c, "runToastProject", 0).visible, false)
    compare(part(c, "runToastProject", 0).text, "")
    compare(part(c, "runToastProject", 1).visible, false, "a project that is not a string")
    compare(part(c, "runToastProject", 1).text, "")
    compare(part(c, "runToastLine", 0).text, "A escalated")
    compare(part(c, "runToastLine", 1).text, "B escalated")
  }

  // Review Focus 4
  function test_a_long_project_name_elides_on_one_line() {
    var name = ""
    for (var i = 0; i < 20; i++) name += "a-very-long-project-name-"
    var c = make([toast(1, "run-a", "A", "escalated", "r", name)])
    var project = part(c, "runToastProject", 0)
    compare(project.text, name)
    compare(project.visible, true)
    compare(project.elide, Text.ElideRight)
    compare(project.truncated, true)
    verify(project.width <= c.width, "inside the card")
    verify(project.height < 2 * part(c, "runToastLine", 0).height, "one line, not wrapped")
  }
}
