import QtQuick
import qs.Commons
import qs.Commons as Cm

// A wrapping row of filter chips. `model` is [{ id, label, count?, tint }];
// a chip's text is its label with the count appended when there is one, and
// its objectName is chipPrefix + id, which is how the view tests find it.
Flow {
  id: row

  property var theme: null
  property var model: []
  property string active: ""
  property bool busy: false
  property string chipPrefix: "chip"

  signal chosen(string id)

  spacing: Style.space(6)

  Repeater {
    model: row.model

    delegate: Chip {
      id: chip
      required property var modelData

      objectName: row.chipPrefix + modelData.id
      theme: row.theme
      busy: row.busy
      active: row.active === modelData.id
      tint: modelData.tint !== undefined ? modelData.tint
        : chip.palette ? chip.palette.dim : Cm.Color.foreground
      text: modelData.count !== undefined ? modelData.label + " " + modelData.count : modelData.label
      onClicked: row.chosen(chip.modelData.id)
    }
  }
}
