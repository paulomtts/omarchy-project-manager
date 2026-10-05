import QtQuick
import QtTest
import "../../ui/components"
import "../../core/domain/projects.js" as Projects
TestCase {
  id: tc
  name: "TypedConfirmDialog"
  when: windowShown
  visible: true
  width: 600; height: 400

  Component { id: dialogC; TypedConfirmDialog { width: 560; height: 360; message: "Remove it?"; detail: "/some/path" } }
  SignalSpy { id: confirmSpy; signalName: "confirmRequested" }
  SignalSpy { id: cancelSpy; signalName: "cancelRequested" }
  SignalSpy { id: typedSpy; signalName: "typedEdited" }

  function find(item, name) {
    if (item.objectName === name) return item
    for (var i = 0; i < item.children.length; i++) { var r = find(item.children[i], name); if (r) return r }
    return null
  }
  function make() {
    var d = createTemporaryObject(dialogC, tc)
    confirmSpy.target = d; cancelSpy.target = d; typedSpy.target = d
    confirmSpy.clear(); cancelSpy.clear(); typedSpy.clear()
    return d
  }

  function test_hidden_until_shown_and_the_accept_button_needs_the_word() {
    var d = make()
    compare(d.visible, false)
    d.shown = true
    compare(d.visible, true)
    compare(find(d, "confirmAccept").enabled, false)
    find(d, "confirmTyped").text = "Delete "
    compare(d.confirmed, true)
    compare(find(d, "confirmAccept").enabled, true)
    d.shown = false
    d.shown = true
    compare(find(d, "confirmTyped").text, "")
  }

  function test_clicks_accept_cancel_and_backdrop() {
    var d = make()
    d.shown = true
    find(d, "confirmTyped").text = "delete"
    var accept = find(d, "confirmAccept")
    mouseClick(accept, accept.width / 2, accept.height / 2)
    compare(confirmSpy.count, 1)
    var cancel = find(d, "confirmCancel")
    mouseClick(cancel, cancel.width / 2, cancel.height / 2)
    compare(cancelSpy.count, 1)
    mouseClick(find(d, "confirmBackdrop"), 2, 2)
    compare(cancelSpy.count, 2)
    mouseClick(find(d, "confirmCard"), 3, 3)
    compare(cancelSpy.count, 2)
  }

  function test_the_typed_field_follows_the_owners_text_and_reports_typing() {
    var d = make()
    d.shown = true
    d.typedText = "del"
    compare(find(d, "confirmTyped").text, "del")
    compare(d.confirmed, false)
    typedSpy.clear()
    find(d, "confirmTyped").text = "delete"
    compare(typedSpy.count, 1)
    compare(typedSpy.signalArguments[0][0], "delete")
    compare(d.confirmed, true)
    compare(find(d, "confirmAccept").enabled, true)
  }

  function test_reopening_shows_the_owners_current_text_not_the_old_typing() {
    var d = make()
    d.shown = true
    d.typedText = "del"
    find(d, "confirmTyped").text = "delete"
    d.shown = false
    compare(find(d, "confirmTyped").text, "")
    d.shown = true
    compare(find(d, "confirmTyped").text, "del")
    d.typedText = "de"
    compare(find(d, "confirmTyped").text, "de")
  }

  function test_busy_blocks_everything_and_errors_show() {
    var d = make()
    d.shown = true
    find(d, "confirmTyped").text = "delete"
    d.busy = true
    compare(find(d, "confirmAccept").enabled, false)
    compare(find(d, "confirmCancel").enabled, false)
    mouseClick(find(d, "confirmBackdrop"), 2, 2)
    compare(cancelSpy.count, 0)
    d.busy = false
    compare(find(d, "confirmError").visible, false)
    d.error = "nope"
    compare(find(d, "confirmError").visible, true)
    compare(find(d, "confirmError").text, "nope")
  }

  // ---- confirmWord ---------------------------------------------------------

  function test_the_default_word_is_delete() {
    var d = make()
    d.shown = true
    compare(d.confirmWord, "delete")
    compare(find(d, "confirmTyped").placeholderText, "delete")
    find(d, "confirmTyped").text = "cancel"
    compare(d.confirmed, false)
    compare(find(d, "confirmAccept").enabled, false)
  }

  function test_the_default_word_agrees_with_projects_isDeleteConfirmed_data() {
    return [
      { tag: "delete", text: "delete" },
      { tag: "Delete-trailing-space", text: "Delete " },
      { tag: "DELETE-leading-space", text: " DELETE" },
      { tag: "del", text: "del" },
      { tag: "empty", text: "" },
      { tag: "deletex", text: "deletex" },
      { tag: "cancel", text: "cancel" }
    ]
  }

  function test_the_default_word_agrees_with_projects_isDeleteConfirmed(data) {
    var d = make()
    d.shown = true
    find(d, "confirmTyped").text = data.text
    compare(d.confirmed, Projects.isDeleteConfirmed(data.text))
    compare(find(d, "confirmAccept").enabled, Projects.isDeleteConfirmed(data.text))
  }

  function test_a_cancel_word_confirms_only_cancel() {
    var d = make()
    d.confirmWord = "cancel"
    d.shown = true
    var field = find(d, "confirmTyped"), accept = find(d, "confirmAccept")
    field.text = "delete"
    compare(d.confirmed, false)
    compare(accept.enabled, false)
    field.text = " Cancel "
    compare(d.confirmed, true)
    compare(accept.enabled, true)
    field.text = "CANCEL"
    compare(d.confirmed, true)
    compare(accept.enabled, true)
    field.text = "cance"
    compare(d.confirmed, false)
    compare(accept.enabled, false)
    field.text = "cancel it"
    compare(d.confirmed, false)
    compare(accept.enabled, false)
  }

  function test_a_cancel_word_accepts_by_click_and_by_return() {
    var d = make()
    d.confirmWord = "cancel"
    d.shown = true
    var field = find(d, "confirmTyped"), accept = find(d, "confirmAccept")
    field.text = "cancel"
    mouseClick(accept, accept.width / 2, accept.height / 2)
    compare(confirmSpy.count, 1)
    field.forceActiveFocus()
    keyClick(Qt.Key_Return)
    compare(confirmSpy.count, 2)
    field.text = "delete"
    field.forceActiveFocus()
    keyClick(Qt.Key_Return)
    compare(confirmSpy.count, 2)
  }

  function test_the_placeholder_follows_the_word() {
    var d = make()
    d.shown = true
    var field = find(d, "confirmTyped")
    d.confirmWord = "cancel"
    compare(field.placeholderText, "cancel")
    d.confirmWord = "remove"
    compare(field.placeholderText, "remove")
  }

  function test_changing_the_word_while_shown_re_evaluates() {
    var d = make()
    d.shown = true
    var accept = find(d, "confirmAccept")
    find(d, "confirmTyped").text = "cancel"
    compare(d.confirmed, false)
    compare(accept.enabled, false)
    d.confirmWord = "cancel"
    compare(d.confirmed, true)
    compare(accept.enabled, true)
    d.confirmWord = "delete"
    compare(d.confirmed, false)
    compare(accept.enabled, false)
  }

  function test_the_word_is_matched_trimmed_and_case_blind() {
    var d = make()
    d.confirmWord = " Cancel "
    d.shown = true
    find(d, "confirmTyped").text = "cancel"
    compare(d.confirmed, true)
    compare(find(d, "confirmAccept").enabled, true)
  }

  function test_an_empty_word_never_confirms_data() {
    return [
      { tag: "empty-word", word: "" },
      { tag: "blank-word", word: "  " }
    ]
  }

  function test_an_empty_word_never_confirms(data) {
    var d = make()
    d.confirmWord = data.word
    d.shown = true
    var field = find(d, "confirmTyped"), accept = find(d, "confirmAccept")
    compare(field.text, "")
    compare(d.confirmed, false)
    compare(accept.enabled, false)
    field.forceActiveFocus()
    keyClick(Qt.Key_Return)
    compare(confirmSpy.count, 0)
    field.text = "delete"
    compare(d.confirmed, false)
    compare(accept.enabled, false)
    field.forceActiveFocus()
    keyClick(Qt.Key_Return)
    compare(confirmSpy.count, 0)
  }

  // ---- confirmWord: review focus --------------------------------------------

  function test_busy_blocks_a_cancel_word() {
    var d = make()
    d.confirmWord = "cancel"
    d.shown = true
    var field = find(d, "confirmTyped")
    field.text = "cancel"
    d.busy = true
    compare(d.confirmed, true)
    compare(find(d, "confirmAccept").enabled, false)
    field.forceActiveFocus()
    keyClick(Qt.Key_Return)
    compare(confirmSpy.count, 0)
  }

  function test_the_owners_text_is_checked_against_the_word() {
    var d = make()
    d.confirmWord = "cancel"
    d.shown = true
    d.typedText = "cancel"
    compare(find(d, "confirmTyped").text, "cancel")
    compare(d.confirmed, true)
    compare(find(d, "confirmAccept").enabled, true)
    d.typedText = "delete"
    compare(d.confirmed, false)
    compare(find(d, "confirmAccept").enabled, false)
  }

  function test_reopening_keeps_the_word_and_clears_the_field() {
    var d = make()
    d.confirmWord = "cancel"
    d.shown = true
    var field = find(d, "confirmTyped")
    field.text = "cancel"
    compare(d.confirmed, true)
    d.shown = false
    d.shown = true
    compare(field.text, "")
    compare(d.confirmWord, "cancel")
    compare(field.placeholderText, "cancel")
    compare(d.confirmed, false)
    field.text = "Cancel"
    compare(d.confirmed, true)
  }

  function test_keypad_enter_accepts_a_cancel_word() {
    var d = make()
    d.confirmWord = "cancel"
    d.shown = true
    var field = find(d, "confirmTyped")
    field.text = "cancel"
    field.forceActiveFocus()
    keyClick(Qt.Key_Enter)
    compare(confirmSpy.count, 1)
  }

  function test_escape_still_cancels_with_a_cancel_word() {
    var d = make()
    d.confirmWord = "cancel"
    d.shown = true
    var field = find(d, "confirmTyped")
    field.text = "cancel"
    field.forceActiveFocus()
    keyClick(Qt.Key_Escape)
    compare(cancelSpy.count, 1)
    compare(confirmSpy.count, 0)
  }
}
