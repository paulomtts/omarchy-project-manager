// tests/ui/components/tst_close_run_dialog.qml
// ui/components/CloseRunDialog.qml: `Close "<title>"?` over a dimmed backdrop,
// what closing does, where else the run is open, the error in urgent, then
// Keep and an orange Close. Close confirms; Keep, the backdrop and Escape
// cancel; Return never confirms; busy blocks every way out and in.
import QtQuick
import QtTest
import "../../helpers/find.js" as H
import "../../../ui/components" as UI

TestCase {
  id: tc
  name: "CloseRunDialog"
  when: windowShown
  visible: true
  width: 640; height: 480

  // A theme with the closeTone token, a colour nothing else uses.
  QtObject {
    id: tokenTheme
    property color foreground: "#eeeeee"
    property color dim: "#777777"
    property color urgent: "#ff3300"
    property string fontFamily: "Token Sans"
    property real bodySize: 15
    property real smallSize: 13
    property real captionSize: 11
    property real headingSize: 19
    property color closeTone: "#aa5500"
  }

  // The same theme without the token, built here so the fallback case holds
  // whether or not T.Theme has grown it.
  QtObject {
    id: plainTheme
    property color foreground: "#eeeeee"
    property color dim: "#777777"
    property color urgent: "#ff3300"
    property string fontFamily: "Plain Sans"
    property real bodySize: 15
    property real smallSize: 13
    property real captionSize: 11
    property real headingSize: 19
  }

  Component { id: dialogC; UI.CloseRunDialog { width: 640; height: 480 } }
  SignalSpy { id: confirms; signalName: "confirmRequested" }
  SignalSpy { id: cancels; signalName: "cancelRequested" }

  readonly property string bodyText: "The run is recorded as cancelled. Nothing is deleted and no branch is touched."

  // A shown dialog for "Fix login" in the token theme; `over` replaces any prop.
  function make(over) {
    var d = createTemporaryObject(dialogC, tc, Object.assign({ shown: true, runTitle: "Fix login", theme: tokenTheme }, over || {}))
    confirms.target = d; cancels.target = d
    confirms.clear(); cancels.clear()
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
    compare(d.objectName, "closeRunDialog")
    verify(H.find(d, "closeDialogCard"), "the modal card")
    verify(H.find(d, "closeDialogBackdrop"), "the backdrop")
    compare(H.find(d, "closeDialogTitle").text, "Close \"Fix login\"?")
    compare(H.find(d, "closeDialogBody").text, tc.bodyText)
    compare(H.find(d, "closeDialogBody").wrapMode, Text.WordWrap)
    compare(H.find(d, "closeDialogOpenIn").visible, false)
    compare(H.find(d, "closeDialogError").visible, false)
    compare(H.find(d, "closeDialogKeep").text, "Keep")
    var accept = H.find(d, "closeDialogAccept")
    compare(accept.text, "Close")
    verify(Qt.colorEqual(accept.foreground, d.closeColor), "Close is painted in the close tone")
  }

  // 2
  function test_blank_title_data() {
    return [
      { tag: "empty", title: "" },
      { tag: "spaces", title: "   " }
    ]
  }

  function test_blank_title(data) {
    var d = make({ runTitle: data.title })
    compare(H.find(d, "closeDialogTitle").text, "Close this run?")
  }

  // 3
  function test_hidden_while_not_shown() {
    var d = make({ shown: false })
    compare(d.visible, false)
    d.shown = true
    compare(d.visible, true)
    d.shown = false
    compare(d.visible, false)
  }

  // 4
  function test_open_in_line() {
    var d = make({ openIn: " 4a51d663 " })
    var line = H.find(d, "closeDialogOpenIn")
    compare(line.visible, true)
    compare(line.text, "A card of this run is also open in run 4a51d663; it stays continuable there.")
    compare(line.wrapMode, Text.WordWrap)
    d.openIn = "  "
    compare(line.visible, false)
  }

  // 5
  function test_close_emits_confirm_once() {
    var d = make()
    click(H.find(d, "closeDialogAccept"))
    compare(confirms.count, 1)
    compare(cancels.count, 0)
  }

  // 6
  function test_keep_backdrop_and_escape_cancel_data() {
    return [
      { tag: "keep", way: "keep" },
      { tag: "backdrop", way: "backdrop" },
      { tag: "escape", way: "escape" }
    ]
  }

  function test_keep_backdrop_and_escape_cancel(data) {
    var d = make()
    if (data.way === "keep") click(H.find(d, "closeDialogKeep"))
    else if (data.way === "backdrop") mouseClick(H.find(d, "closeDialogBackdrop"), 2, 2)
    else keyClick(Qt.Key_Escape)
    compare(cancels.count, 1)
    compare(confirms.count, 0)
    mouseClick(H.find(d, "closeDialogCard"), 3, 3)
    compare(cancels.count, 1, "a click on the card does not cancel")
  }

  // 7
  function test_return_does_not_confirm() {
    var d = make()
    keyClick(Qt.Key_Return)
    keyClick(Qt.Key_Enter)
    compare(confirms.count, 0)
    compare(cancels.count, 0)
  }

  // 8
  function test_busy_blocks_everything() {
    var d = make({ busy: true })
    var keep = H.find(d, "closeDialogKeep"), accept = H.find(d, "closeDialogAccept")
    compare(keep.enabled, false)
    compare(accept.enabled, false)
    click(accept)
    click(keep)
    mouseClick(H.find(d, "closeDialogBackdrop"), 2, 2)
    keyClick(Qt.Key_Escape)
    compare(confirms.count, 0)
    compare(cancels.count, 0)
    compare(keep.text, "Keep")
    compare(accept.text, "Close")
    d.busy = false
    compare(keep.enabled, true)
    compare(accept.enabled, true)
    click(accept)
    compare(confirms.count, 1)
    keyClick(Qt.Key_Escape)
    compare(cancels.count, 1, "Escape works again")
  }

  // 9
  function test_error_shows_and_dialog_stays() {
    var d = make()
    var line = H.find(d, "closeDialogError")
    d.error = "The run is busy."
    compare(line.visible, true)
    compare(line.text, "The run is busy.")
    verify(Qt.colorEqual(line.color, tokenTheme.urgent), "in the theme's urgent")
    compare(line.wrapMode, Text.WordWrap)
    compare(d.shown, true)
    compare(d.visible, true)
    d.error = ""
    compare(line.visible, false)
  }

  // 10
  function test_close_tone_token_and_fallback() {
    var d = make()
    verify(Qt.colorEqual(H.find(d, "closeDialogAccept").foreground, "#aa5500"), "the token")
    var plain = make({ theme: plainTheme })
    verify(Qt.colorEqual(H.find(plain, "closeDialogAccept").foreground, "#ff9442"), "the fallback orange")
  }

  // 11
  function test_never_writes_its_props() {
    var d = make({ openIn: "4a51d663", error: "x" })
    click(H.find(d, "closeDialogAccept"))
    click(H.find(d, "closeDialogKeep"))
    keyClick(Qt.Key_Escape)
    compare(confirms.count, 1)
    compare(cancels.count, 2)
    compare(d.shown, true)
    compare(d.error, "x")
    compare(d.runTitle, "Fix login")
    compare(d.openIn, "4a51d663")
    compare(d.busy, false)
  }

  // Review Focus 1: once hidden, Escape reaches nothing.
  function test_escape_on_a_hidden_dialog_does_nothing() {
    var d = make()
    d.shown = false
    wait(0)
    keyClick(Qt.Key_Escape)
    compare(cancels.count, 0)
  }

  // Review Focus 2: a dialog shown again takes the focus again, unprompted.
  function test_reopening_takes_the_focus_again() {
    var d = make({ shown: false })
    d.shown = true
    wait(0)
    verify(d.focusItem.activeFocus, "showing it focuses the key item")
    keyClick(Qt.Key_Escape)
    compare(cancels.count, 1)
    d.shown = false
    wait(0)
    d.shown = true
    wait(0)
    keyClick(Qt.Key_Escape)
    compare(cancels.count, 2)
  }

  // Review Focus 3: the focus item is the key item, never a button.
  function test_focus_item_is_not_a_button() {
    var d = make()
    verify(d.focusItem, "a focus item")
    compare(d.focusItem.objectName, "closeDialogKeys")
    verify(d.focusItem.activeFocus)
  }

  // Review Focus 4: a long title elides, a long open-in and error wrap, and
  // the buttons stay inside the card.
  function test_long_text_keeps_the_buttons_in_the_card() {
    var long = "word ".repeat(80)
    var d = make({ runTitle: long, openIn: long, error: long })
    wait(30)
    var card = H.find(d, "closeDialogCard"), title = H.find(d, "closeDialogTitle")
    compare(title.elide, Text.ElideRight)
    verify(title.truncated, "the title elides")
    compare(title.lineCount, 1)
    verify(H.find(d, "closeDialogOpenIn").lineCount > 1, "open-in wraps")
    verify(H.find(d, "closeDialogError").lineCount > 1, "the error wraps")
    var accept = H.find(d, "closeDialogAccept")
    var p = accept.mapToItem(card, 0, 0)
    verify(p.x + accept.width <= card.width, "Close is inside the card's width")
    verify(p.y + accept.height <= card.height, "Close is inside the card's height")
  }

  // Review Focus 5: a title with quotes or markup is shown verbatim.
  function test_title_is_plain_text() {
    var d = make({ runTitle: "<b>\"x\"</b>" })
    var title = H.find(d, "closeDialogTitle")
    compare(title.textFormat, Text.PlainText)
    compare(title.text, "Close \"<b>\"x\"</b>\"?")
  }

  // A null theme (teardown) paints the fallbacks and throws nothing.
  function test_a_null_theme_and_destroy_are_quiet() {
    var d = make()
    d.theme = null
    wait(0)
    verify(Qt.colorEqual(d.closeColor, "#ff9442"))
    d.destroy()
    wait(0)
  }
}
