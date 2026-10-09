import QtQuick
import qs.Commons
import qs.Ui
import "../components" as UI
import "../theme" as T

// The verify editor: a `Verify` caption, one text row per stored command, `+`,
// and the `run without any verification` chip. Reads `commands` and
// `allowNoVerification` and never changes them: an edit, `+` or `✕` emits
// commandsEdited(list), the whole list of rows padded with "" and as strings;
// the chip emits allowNoVerificationEdited(!active); every key pressed in a row
// goes out unhandled as keyPressed(event). A row emits only when its text
// differs from the stored command, so feeding a list back echoes nothing.
// Inner objectNames start with objectNamePrefix: <P>VerifyLabel, <P>Verify<i>,
// <P>VerifyRemove<i>, <P>VerifyAdd, <P>NoVerify.
Column {
  id: field
  spacing: Style.space(8)

  // Colours and fonts; null falls back to the shell's Color.
  property var theme: T.Theme {}
  // A list, or the array-like a list arrives as through createObject; anything
  // else reads as [].
  property var commands: []
  property bool allowNoVerification: false
  // False disables every row, remove and `+`, and makes the chip busy.
  property bool editable: true
  property string objectNamePrefix: "field"

  // The rows are counted, not listed: a list of the same length keeps every
  // row (its focus, its cursor).
  readonly property int rows: Math.max(1, field.stored().length)

  readonly property color foregroundColor: field.theme ? field.theme.foreground : Color.foreground
  readonly property color urgentColor: field.theme ? field.theme.urgent : Color.urgent
  readonly property color dimColor: field.theme ? field.theme.dim : Color.foreground

  signal commandsEdited(var commands)
  signal allowNoVerificationEdited(bool on)
  signal keyPressed(var event)

  onCommandsChanged: field.sync()

  function stored() {
    var list = field.commands
    if (!list || typeof list !== "object" || typeof list.length !== "number") return []
    return Array.prototype.slice.call(list)
  }

  function commandAt(index) {
    var value = field.stored()[index]
    return value === undefined || value === null ? "" : String(value)
  }

  // A fresh copy of the stored commands, padded with "" to the rows shown.
  function padded() {
    var list = []
    for (var i = 0; i < field.rows; i++) list.push(field.commandAt(i))
    return list
  }

  function edit(index, text) {
    var list = field.padded()
    list[index] = text
    field.commandsEdited(list)
  }

  function remove(index) {
    var list = field.padded()
    list.splice(index, 1)
    field.commandsEdited(list)
  }

  function add() {
    var list = field.padded()
    list.push("")
    field.commandsEdited(list)
  }

  // Sets every row's text to its stored command, touching only rows that
  // differ; emits nothing. New rows sync themselves when they are made.
  function sync() {
    for (var i = 0; i < rowRepeater.count; i++) {
      var row = rowRepeater.itemAt(i)
      if (row) row.sync()
    }
  }

  UI.ThemedText {
    objectName: field.objectNamePrefix + "VerifyLabel"
    variant: "caption"
    theme: field.theme
    text: "Verify"
  }

  Repeater {
    id: rowRepeater
    model: field.rows

    Row {
      id: commandRow
      required property int index
      width: parent ? parent.width : 0
      spacing: Style.space(8)

      function sync() {
        var want = field.commandAt(commandRow.index)
        if (commandField.text !== want) commandField.text = want
      }

      Component.onCompleted: commandRow.sync()

      TextField {
        id: commandField
        objectName: field.objectNamePrefix + "Verify" + commandRow.index
        width: Math.max(0, commandRow.width - (removeButton.visible ? removeButton.width + commandRow.spacing : 0))
        foreground: field.foregroundColor
        placeholderText: "uv run pytest"
        enabled: field.editable
        onTextChanged: if (text !== field.commandAt(commandRow.index)) field.edit(commandRow.index, text)
        Keys.onPressed: function(event) { field.keyPressed(event) }
      }

      UI.ActionButton {
        id: removeButton
        objectName: field.objectNamePrefix + "VerifyRemove" + commandRow.index
        visible: field.rows >= 2
        text: "✕"
        enabled: field.editable
        theme: field.theme
        onClicked: field.remove(commandRow.index)
      }
    }
  }

  UI.ActionButton {
    objectName: field.objectNamePrefix + "VerifyAdd"
    text: "+"
    enabled: field.editable
    theme: field.theme
    onClicked: field.add()
  }

  // The opt-out from verification is a chip, not a checkbox.
  UI.Chip {
    id: noVerifyChip
    objectName: field.objectNamePrefix + "NoVerify"
    theme: field.theme
    text: "run without any verification"
    active: field.allowNoVerification
    busy: !field.editable
    tint: noVerifyChip.active ? field.urgentColor : field.dimColor
    onClicked: field.allowNoVerificationEdited(!noVerifyChip.active)
  }
}
