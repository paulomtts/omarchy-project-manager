import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Commons as Cm
import "../theme" as T

// The bordered multi-line editor the panel uses for raw note text: a tinted
// box whose border brightens while it is being edited, wrapped around a
// plain TextArea. Which chord asks the owner to submit is the caller's
// choice: nothing submits unless `submitChords` lists it.
Rectangle {
  id: box

  // The owner's Theme, or none: `palette` then falls back to its own. Both
  // are objects, and tearing a view down nulls them while the bindings below
  // still run once, so every read of `palette` is guarded.
  property var theme: null
  // The editor owns its text, exactly as the hand-rolled boxes did: typing
  // replaces a binding here, and the owner is told through `edited`.
  property alias text: editor.text
  property string placeholder: ""
  property real minHeight: Style.space(160)
  // The callers' tests look the editor up by name.
  property string editorObjectName: "textAreaEditor"
  // The chords that emit submitRequested: "ctrl-s" and/or "ctrl-enter".
  // Empty by default so the component never adds a shortcut on its own.
  property var submitChords: []

  readonly property var palette: box.theme || boxTheme
  readonly property Item editorItem: editor
  readonly property color tint: box.palette ? box.palette.foreground : Cm.Color.foreground

  signal edited(string text)
  signal escapePressed()
  signal submitRequested()

  height: Math.max(box.minHeight, editor.implicitHeight + Style.space(16))
  radius: Style.space(6)
  color: Qt.alpha(box.tint, 0.06)
  border.width: 1
  border.color: editor.activeFocus ? box.tint : Qt.alpha(box.tint, 0.3)

  T.Theme { id: boxTheme }

  Controls.TextArea {
    id: editor
    objectName: box.editorObjectName
    anchors.fill: parent
    anchors.margins: Style.space(8)
    background: null
    placeholderText: box.placeholder
    color: box.tint
    font.family: box.palette ? box.palette.fontFamily : Style.font.family
    font.pixelSize: Style.font.bodySmall
    wrapMode: TextEdit.Wrap
    selectByMouse: true

    onTextChanged: box.edited(text)

    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Escape) { box.escapePressed(); event.accepted = true; return }
      if (!(event.modifiers & Qt.ControlModifier)) return
      var chords = box.submitChords || []
      var chord = event.key === Qt.Key_S ? "ctrl-s"
        : (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) ? "ctrl-enter" : ""
      if (chord !== "" && chords.indexOf(chord) !== -1) {
        box.submitRequested(); event.accepted = true
      }
    }
  }
}
