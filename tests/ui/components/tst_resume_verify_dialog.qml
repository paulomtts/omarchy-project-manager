import QtQuick
import QtTest
import "../../helpers/find.js" as H
import "../../../ui/components" as UI

TestCase {
  id: tc
  name: "ResumeVerifyDialog"
  when: windowShown
  visible: true
  width: 640; height: 700

  Component { id: dialogC; UI.ResumeVerifyDialog { width: 640; height: 700 } }
  SignalSpy { id: edits; signalName: "commandsEdited" }
  SignalSpy { id: optOuts; signalName: "allowNoVerificationEdited" }
  SignalSpy { id: confirms; signalName: "confirmRequested" }
  SignalSpy { id: cancels; signalName: "cancelRequested" }

  readonly property string bodyText: "am does not record the verify commands. They run for every subtask without a checkpoint, merged bases and Integrate."
  readonly property string savedText: "Saved for this project and reused by later resumes and dispatches."

  // A shown dialog for run …4a51d663 with no commands; `over` replaces any prop.
  function make(over) {
    var d = createTemporaryObject(dialogC, tc, Object.assign({ shown: true, runLabel: "…4a51d663", commands: [] }, over || {}))
    edits.target = d; optOuts.target = d; confirms.target = d; cancels.target = d
    edits.clear(); optOuts.clear(); confirms.clear(); cancels.clear()
    wait(30)
    return d
  }
  // A freshly laid-out item is placed on the next frame: wait, so the click
  // lands on the item and not where it was.
  function click(item) { wait(30); mouseClick(item, item.width / 2, item.height / 2) }

  // 1
  function test_renders_the_wording() {
    var d = make()
    compare(d.visible, true)
    compare(d.objectName, "resumeVerifyDialog")
    verify(H.find(d, "resumeDialogCard"), "the modal card")
    verify(H.find(d, "resumeDialogBackdrop"), "the backdrop")
    compare(H.find(d, "resumeDialogTitle").text, "Resume run …4a51d663")
    compare(H.find(d, "resumeDialogBody").text, tc.bodyText)
    compare(H.find(d, "resumeDialogBody").wrapMode, Text.WordWrap)
    compare(H.find(d, "resumeDialogSaved").text, tc.savedText)
    compare(H.find(d, "resumeDialogSaved").wrapMode, Text.WordWrap)
    verify(H.find(d, "resumeVerifyLabel"), "the Verify caption")
    verify(H.find(d, "resumeVerify0"), "the first verify row")
    verify(H.find(d, "resumeVerifyAdd"), "the + button")
    verify(H.find(d, "resumeNoVerify"), "the opt-out chip")
    compare(H.find(d, "resumeNoVerify").text, "run without any verification")
    compare(H.find(d, "resumeDialogCancel").text, "Cancel")
    var accept = H.find(d, "resumeDialogAccept")
    compare(accept.text, "Resume")
    compare(accept.iconText, "⟳")
    compare(H.find(d, "resumeDialogError").visible, false)
  }

  // 2
  function test_hidden_while_not_shown() {
    var d = make({ shown: false })
    compare(d.visible, false)
    d.shown = true
    compare(d.visible, true)
  }

  // 3
  function test_resume_follows_the_verify_rule_data() {
    return [
      { tag: "empty-list", commands: [], allow: false, can: false },
      { tag: "one-blank", commands: [""], allow: false, can: false },
      { tag: "only-spaces", commands: ["  "], allow: false, can: false },
      { tag: "null", commands: null, allow: false, can: false },
      { tag: "a-string", commands: "x", allow: false, can: false },
      { tag: "blank-then-command", commands: ["", "a"], allow: false, can: true },
      { tag: "opt-out-no-rows", commands: [], allow: true, can: true }
    ]
  }

  function test_resume_follows_the_verify_rule(data) {
    var d = make({ commands: data.commands, allowNoVerification: data.allow })
    compare(d.canResume, data.can)
    compare(H.find(d, "resumeDialogAccept").enabled, data.can)
  }

  // 4
  function test_edits_are_forwarded_and_change_nothing_here() {
    var d = make()
    H.find(d, "resumeVerify0").text = "bash tests/run.sh"
    compare(edits.count, 1)
    compare(edits.signalArguments[0][0], ["bash tests/run.sh"])
    click(H.find(d, "resumeNoVerify"))
    compare(optOuts.count, 1)
    compare(optOuts.signalArguments[0][0], true)
    compare(d.commands.length, 0, "the dialog never changes its commands")
    compare(d.allowNoVerification, false, "nor its opt-out")
    compare(confirms.count, 0)
    compare(cancels.count, 0)
  }

  // 5
  function test_resume_confirms_only_when_enabled() {
    var d = make({ commands: [] })
    click(H.find(d, "resumeDialogAccept"))
    compare(confirms.count, 0)
    d.commands = ["a"]
    wait(450)
    click(H.find(d, "resumeDialogAccept"))
    compare(confirms.count, 1)
    compare(cancels.count, 0)
  }

  // 6
  function test_cancel_backdrop_and_escape_cancel() {
    var d = make({ commands: ["a"] })
    click(H.find(d, "resumeDialogCancel"))
    compare(cancels.count, 1)
    mouseClick(H.find(d, "resumeDialogBackdrop"), 2, 2)
    compare(cancels.count, 2)
    mouseClick(H.find(d, "resumeDialogCard"), 3, 3)
    compare(cancels.count, 2, "a click on the card does not cancel")
    H.find(d, "resumeVerify0").forceActiveFocus()
    keyClick(Qt.Key_Escape)
    compare(cancels.count, 3)
    compare(confirms.count, 0)
  }

  // 7
  function test_return_does_not_confirm() {
    var d = make({ commands: ["a"] })
    compare(d.canResume, true)
    H.find(d, "resumeVerify0").forceActiveFocus()
    keyClick(Qt.Key_Return)
    keyClick(Qt.Key_Enter)
    compare(confirms.count, 0)
    compare(cancels.count, 0)
  }

  // 8
  function test_error_shows_in_urgent() {
    var d = make({ error: "Another am process…" })
    var line = H.find(d, "resumeDialogError")
    compare(line.visible, true)
    compare(line.text, "Another am process…")
    compare(line.color, d.theme.urgent)
    compare(line.wrapMode, Text.WordWrap)
    d.error = ""
    compare(line.visible, false)
  }

  // 9
  function test_focus_item_is_the_first_row() {
    var d = make()
    verify(d.focusItem, "a focus item")
    compare(d.focusItem.objectName, "resumeVerify0")
  }

  // Review Focus 1: the field makes its rows again when their count changes.
  function test_focus_item_follows_the_rows_as_they_are_made_again() {
    var d = make()
    d.commands = ["a", "b"]
    wait(0)
    compare(d.focusItem, H.find(d, "resumeVerify0"))
    compare(d.focusItem.text, "a")
    d.commands = []
    wait(0)
    compare(d.focusItem, H.find(d, "resumeVerify0"))
    compare(d.focusItem.text, "")
    d.focusItem.forceActiveFocus()
    verify(d.focusItem.activeFocus, "the live row takes the keyboard")
  }

  // 10
  function test_a_null_theme_and_commands_and_destroy_are_quiet() {
    var d = make({ commands: ["a"] })
    d.theme = null
    d.commands = null
    wait(0)
    compare(d.canResume, false)
    compare(edits.count, 0)
    d.destroy()
    wait(0)
  }
}
