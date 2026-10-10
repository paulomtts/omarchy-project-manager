import QtQuick
import qs.Commons

// The shape both list sections share: a row of filter chips, optionally an
// item of the caller's under it, one status line instead of the rows when
// there is something to say, and the rows themselves. The caller supplies the
// row delegate and every piece of wording, so nothing domain-specific lives
// here.
Column {
  id: list

  property var theme: null
  property var model: []
  // [{ id, label, count?, tint }], as ChipRow takes it.
  property var chips: []
  property string activeChip: ""
  property Component rowDelegate: null
  // Made once, directly under the chip row and above the status line, when
  // not null; shown while chipsFooterShown is true and the chip row's rule
  // holds (not loading, no error). Hidden, it takes no height and no gap.
  property Component chipsFooter: null
  property bool chipsFooterShown: true

  // The callers' tests look the chip row, the chips and the status up by name.
  property string chipsObjectName: "chips"
  property string chipPrefix: "chip"
  property string statusObjectName: "listStatus"

  property bool loading: false
  property string loadingText: ""
  property string error: ""
  property bool empty: false
  property bool filtered: false
  property string emptyText: ""
  property string filteredText: ""

  signal chipToggled(string id)

  spacing: Style.space(6)

  ChipRow {
    objectName: list.chipsObjectName
    visible: list.chips.length > 0 && !list.loading && list.error === ""
    width: parent.width
    theme: list.theme
    chipPrefix: list.chipPrefix
    active: list.activeChip
    model: list.chips
    onChosen: function(id) { list.chipToggled(id) }
  }

  Loader {
    objectName: list.chipsObjectName + "Footer"
    width: parent.width
    sourceComponent: list.chipsFooter
    visible: list.chipsFooter !== null && list.chipsFooterShown && !list.loading && list.error === ""
  }

  ListStatus {
    objectName: list.statusObjectName
    theme: list.theme
    width: parent.width
    loading: list.loading
    loadingText: list.loadingText
    error: list.error
    empty: list.empty
    filtered: list.filtered
    emptyText: list.emptyText
    filteredText: list.filteredText
  }

  Repeater {
    model: list.loading || list.error !== "" ? [] : list.model
    delegate: list.rowDelegate
  }
}
