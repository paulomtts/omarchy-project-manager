import QtQuick
import QtTest
import "../../helpers/find.js" as H
import "../../../ui/components" as UI

TestCase {
  id: tc
  name: "VerifyCommandsField"
  when: windowShown
  visible: true
  width: 480; height: 400

  Component { id: fieldC; UI.VerifyCommandsField { width: 480 } }
  SignalSpy { id: edits; signalName: "commandsEdited" }
  SignalSpy { id: optOuts; signalName: "allowNoVerificationEdited" }
  SignalSpy { id: keys; signalName: "keyPressed" }

  property int lastKey: -1

  function make(props) {
    var f = createTemporaryObject(fieldC, tc, props || {})
    edits.target = f; optOuts.target = f; keys.target = f
    edits.clear(); optOuts.clear(); keys.clear()
    tc.lastKey = -1
    wait(30)
    return f
  }
  // A row that just appeared is laid out on the next frame: wait for it, so
  // the click lands on the item and not where it was.
  function click(item) { wait(30); mouseClick(item, item.width / 2, item.height / 2) }

  function test_it_renders_one_row_per_command() {
    var f = make({ commands: ["a", "b"] })
    compare(H.find(f, "fieldVerifyLabel").text, "Verify")
    compare(H.find(f, "fieldVerify0").text, "a")
    compare(H.find(f, "fieldVerify1").text, "b")
    verify(!H.find(f, "fieldVerify2"), "two rows only")
    compare(H.find(f, "fieldVerify0").placeholderText, "uv run pytest")
    compare(f.rows, 2)
    compare(edits.count, 0)
  }

  function test_missing_or_malformed_commands_read_as_one_empty_row_data() {
    return [
      { tag: "empty", props: { commands: [] } },
      { tag: "null", props: { commands: null } },
      { tag: "a-string", props: { commands: "uv run pytest" } },
      { tag: "a-number", props: { commands: 3 } },
      { tag: "unset", props: {} }
    ]
  }

  function test_missing_or_malformed_commands_read_as_one_empty_row(data) {
    var f = make(data.props)
    compare(f.rows, 1)
    compare(H.find(f, "fieldVerify0").text, "")
    verify(!H.find(f, "fieldVerify1"), "one row only")
    var remove = H.find(f, "fieldVerifyRemove0")
    verify(!remove || !remove.visible, "no remove on the only row")
    compare(edits.count, 0)
  }

  function test_an_edit_sends_the_whole_list() {
    var f = make({ commands: ["a", "b"] })
    H.find(f, "fieldVerify1").text = "b2"
    compare(edits.count, 1)
    compare(edits.signalArguments[0][0], ["a", "b2"])
  }

  function test_an_edit_fed_back_echoes_nothing_and_keeps_the_row() {
    var f = make({ commands: ["a"] })
    var row0 = H.find(f, "fieldVerify0")
    row0.forceActiveFocus()
    row0.text = "a2"
    compare(edits.count, 1)
    f.commands = edits.signalArguments[0][0]
    verify(H.find(f, "fieldVerify0") === row0, "the same row, not a new one")
    compare(row0.text, "a2")
    verify(row0.activeFocus, "still focused")
    compare(edits.count, 1)
  }

  function test_a_new_list_from_the_owner_echoes_nothing() {
    var f = make({ commands: ["a"] })
    f.commands = ["x", "y"]
    compare(H.find(f, "fieldVerify0").text, "x")
    compare(H.find(f, "fieldVerify1").text, "y")
    compare(edits.count, 0)
  }

  function test_plus_appends_an_empty_command() {
    var f = make({ commands: ["a"] })
    click(H.find(f, "fieldVerifyAdd"))
    compare(edits.count, 1)
    compare(edits.signalArguments[0][0], ["a", ""])
    f.commands = ["a", ""]
    verify(H.find(f, "fieldVerify1"), "the new row")
    compare(H.find(f, "fieldVerify1").text, "")
    verify(H.find(f, "fieldVerifyRemove0").visible)
    verify(H.find(f, "fieldVerifyRemove1").visible)
    compare(edits.count, 1, "the new row echoes nothing")
  }

  function test_plus_on_an_empty_list_gives_two_empty_commands() {
    var f = make({ commands: [] })
    click(H.find(f, "fieldVerifyAdd"))
    compare(edits.count, 1)
    compare(edits.signalArguments[0][0], ["", ""])
  }

  function test_remove_drops_that_row() {
    var f = make({ commands: ["a", "b"] })
    click(H.find(f, "fieldVerifyRemove1"))
    compare(edits.count, 1)
    compare(edits.signalArguments[0][0], ["a"])
    click(H.find(f, "fieldVerifyRemove0"))
    compare(edits.count, 2)
    compare(edits.signalArguments[1][0], ["b"])
  }

  function test_a_remove_fed_back_leaves_the_remaining_command() {
    var f = make({ commands: ["a", "b"] })
    click(H.find(f, "fieldVerifyRemove0"))
    compare(edits.signalArguments[0][0], ["b"])
    f.commands = ["b"]
    wait(0)
    compare(H.find(f, "fieldVerify0").text, "b")
    verify(!H.find(f, "fieldVerify1"), "one row only")
    verify(!H.find(f, "fieldVerifyRemove0").visible, "no remove on the only row")
    compare(edits.count, 1)
  }

  function test_one_row_has_no_remove() {
    var f = make({ commands: ["a"] })
    var remove = H.find(f, "fieldVerifyRemove0")
    verify(!remove || !remove.visible)
  }

  function test_a_null_command_reads_as_empty_and_goes_out_as_empty() {
    var f = make({ commands: ["a", null] })
    compare(H.find(f, "fieldVerify1").text, "")
    compare(edits.count, 0)
    H.find(f, "fieldVerify0").text = "a2"
    compare(edits.count, 1)
    compare(edits.signalArguments[0][0], ["a2", ""])
  }

  function test_sync_resets_an_unfed_row_and_emits_nothing() {
    var f = make({ commands: ["a"] })
    var row0 = H.find(f, "fieldVerify0")
    row0.text = "typed"
    compare(edits.count, 1)
    compare(row0.text, "typed", "kept until the owner says otherwise")
    f.sync()
    compare(row0.text, "a")
    compare(edits.count, 1)
  }

  function test_the_opt_out_chip_emits_the_flip_and_waits_for_the_owner() {
    var f = make({ commands: ["a"] })
    var chip = H.find(f, "fieldNoVerify")
    compare(chip.text, "run without any verification")
    compare(chip.active, false)
    click(chip)
    compare(optOuts.count, 1)
    compare(optOuts.signalArguments[0][0], true)
    compare(chip.active, false, "the field never changes its own input")
    f.allowNoVerification = true
    compare(chip.active, true)
    click(chip)
    compare(optOuts.count, 2)
    compare(optOuts.signalArguments[1][0], false)
    compare(edits.count, 0)
  }

  function test_not_editable_disables_everything_and_emits_nothing() {
    var f = make({ commands: ["a", "b"], editable: false })
    compare(H.find(f, "fieldVerify0").enabled, false)
    compare(H.find(f, "fieldVerify1").enabled, false)
    compare(H.find(f, "fieldVerifyRemove0").enabled, false)
    compare(H.find(f, "fieldVerifyAdd").enabled, false)
    compare(H.find(f, "fieldNoVerify").busy, true)
    click(H.find(f, "fieldVerifyAdd"))
    click(H.find(f, "fieldVerifyRemove0"))
    click(H.find(f, "fieldNoVerify"))
    compare(edits.count, 0)
    compare(optOuts.count, 0)
  }

  function test_keys_in_a_row_are_forwarded() {
    var f = make({ commands: ["a"] })
    f.keyPressed.connect(function(event) { tc.lastKey = event.key })
    H.find(f, "fieldVerify0").forceActiveFocus()
    keyClick(Qt.Key_Escape)
    compare(keys.count, 1)
    compare(tc.lastKey, Qt.Key_Escape)
  }

  function test_the_prefix_renames_every_inner_item() {
    var f = make({ commands: ["a", "b"], objectNamePrefix: "resume" })
    verify(H.find(f, "resumeVerifyLabel"))
    verify(H.find(f, "resumeVerify0"))
    verify(H.find(f, "resumeVerifyRemove0"))
    verify(H.find(f, "resumeVerifyAdd"))
    verify(H.find(f, "resumeNoVerify"))
    verify(!H.find(f, "fieldVerify0"), "no default names left")
  }

  function test_a_null_theme_and_destroy_are_quiet() {
    var f = make({ commands: ["a", "b"], allowNoVerification: true })
    f.theme = null
    wait(0)
    compare(H.find(f, "fieldVerify0").text, "a")
    f.commands = null
    wait(0)
    compare(H.find(f, "fieldVerify0").text, "")
    compare(edits.count, 0)
    f.destroy()
    wait(0)
  }
}
