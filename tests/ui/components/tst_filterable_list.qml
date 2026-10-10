import QtQuick
import QtTest
import qs.Commons
import "../../helpers/find.js" as H
import "../../../ui/components" as UI
import "../../../ui/theme" as T

TestCase {
  id: tc
  name: "FilterableList"
  when: windowShown
  visible: true
  width: 400; height: 500

  T.Theme { id: tcTheme; foreground: "#00ff00" }

  Component {
    id: listC
    UI.FilterableList {
      width: 360
      theme: tcTheme
      chipsObjectName: "myChips"
      chipPrefix: "myChip"
      statusObjectName: "myStatus"
      loadingText: "Loading things…"
      emptyText: "Nothing here."
      filteredText: "Nothing matches."
      rowDelegate: Component {
        UI.ListRow {
          required property var modelData
          required index
          objectName: "myRow" + index
          width: 360
          theme: tcTheme
          UI.ThemedText { objectName: "myRowLabel" + parent.parent.index; theme: tcTheme; text: parent.parent.modelData.label }
        }
      }
    }
  }

  SignalSpy { id: chipSpy; signalName: "chipToggled" }

  // How many footer items the slot has made.
  property int footersMade: 0

  Component {
    id: footerC
    Rectangle {
      objectName: "myFooter"
      width: 10
      height: 20
      Component.onCompleted: tc.footersMade += 1
    }
  }

  // An item's top edge in the list's coordinates.
  function topIn(list, name) { return H.find(list, name).mapToItem(list, 0, 0).y }

  property var rows: [{ label: "one" }, { label: "two" }]
  property var chips: [{ id: "a", label: "Alpha", count: 1 }, { id: "b", label: "Beta", count: 2 }]

  function make() {
    var list = createTemporaryObject(listC, tc)
    chipSpy.target = list
    chipSpy.clear()
    tc.footersMade = 0
    return list
  }

  function test_the_chips_carry_the_prefix_the_label_and_the_count() {
    var list = make()
    list.chips = chips
    wait(20)
    compare(H.find(list, "myChips").visible, true)
    compare(H.find(list, "myChipa").text, "Alpha 1")
    compare(H.find(list, "myChipb").text, "Beta 2")
  }

  function test_clicking_a_chip_reports_its_id() {
    var list = make()
    list.chips = chips
    wait(20)
    var chip = H.find(list, "myChipb")
    mouseClick(chip, chip.width / 2, chip.height / 2)
    compare(chipSpy.count, 1)
    compare(chipSpy.signalArguments[0][0], "b")
  }

  function test_the_active_chip_is_marked() {
    var list = make()
    list.chips = chips
    list.activeChip = "b"
    wait(20)
    compare(H.find(list, "myChipb").active, true)
    compare(H.find(list, "myChipa").active, false)
  }

  function test_the_chips_are_hidden_without_chips_and_while_loading_or_failed() {
    var list = make()
    compare(H.find(list, "myChips").visible, false)
    list.chips = chips
    wait(20)
    compare(H.find(list, "myChips").visible, true)
    list.loading = true
    compare(H.find(list, "myChips").visible, false)
    list.loading = false
    list.error = "boom"
    compare(H.find(list, "myChips").visible, false)
  }

  function test_the_rows_come_from_the_model_through_the_row_delegate() {
    var list = make()
    list.model = rows
    wait(20)
    verify(H.find(list, "myRow0"))
    verify(H.find(list, "myRow1"))
    verify(!H.find(list, "myRow2"))
    compare(H.find(list, "myRowLabel1").text, "two")
  }

  function test_no_rows_are_shown_while_loading_or_after_an_error() {
    var list = make()
    list.model = rows
    wait(20)
    verify(H.find(list, "myRow0"))
    list.loading = true
    wait(20)
    verify(!H.find(list, "myRow0"))
    list.loading = false
    list.error = "boom"
    wait(20)
    verify(!H.find(list, "myRow0"))
  }

  function test_the_status_line_follows_the_lists_state() {
    var list = make()
    list.loading = true
    compare(H.find(list, "myStatus").text, "Loading things…")
    list.loading = false
    list.empty = true
    compare(H.find(list, "myStatus").text, "Nothing here.")
    list.filtered = true
    compare(H.find(list, "myStatus").text, "Nothing matches.")
    list.error = "boom"
    compare(H.find(list, "myStatus").text, "boom")
    list.error = ""
    list.empty = false
    compare(H.find(list, "myStatus").visible, false)
  }

  function test_without_a_footer_nothing_is_added_and_the_layout_is_unchanged() {
    var list = make()
    list.chips = chips
    list.model = rows
    wait(20)
    var slot = H.find(list, "myChipsFooter")
    verify(slot, "the slot exists")
    compare(slot.item, null, "nothing is created")
    compare(slot.visible, false)
    compare(tc.footersMade, 0)
    compare(topIn(list, "myRow0"), topIn(list, "myChips") + H.find(list, "myChips").height + list.spacing,
            "the first row follows the chips with one gap")
  }

  function test_a_footer_is_made_once_under_the_chips_and_above_the_status_line() {
    var list = make()
    list.chipsFooter = footerC
    list.chips = chips
    list.empty = true
    wait(20)
    compare(tc.footersMade, 1)
    var footer = H.find(list, "myFooter")
    verify(footer)
    compare(footer.visible, true)
    compare(footer.width, 360, "the slot gives the footer the list's width")
    verify(topIn(list, "myChips") < topIn(list, "myFooter"), "under the chips")
    compare(topIn(list, "myStatus"), topIn(list, "myFooter") + 20 + list.spacing, "the status line follows it")
    list.chips = [{ id: "c", label: "Gamma" }]
    list.empty = false
    list.model = rows
    wait(20)
    compare(tc.footersMade, 1, "never made again")
  }

  function test_the_footer_hides_while_loading_or_failed_like_the_chips() {
    var list = make()
    list.chipsFooter = footerC
    list.chips = chips
    wait(20)
    compare(H.find(list, "myFooter").visible, true)
    list.loading = true
    compare(H.find(list, "myFooter").visible, false)
    list.loading = false
    list.error = "boom"
    compare(H.find(list, "myFooter").visible, false)
    list.error = ""
    compare(H.find(list, "myFooter").visible, true)
  }

  function test_a_footer_the_owner_hides_takes_no_height_and_no_gap() {
    var list = make()
    list.chipsFooter = footerC
    list.chips = chips
    list.empty = true
    list.chipsFooterShown = false
    wait(20)
    compare(H.find(list, "myFooter").visible, false)
    compare(topIn(list, "myStatus"), topIn(list, "myChips") + H.find(list, "myChips").height + list.spacing,
            "the status line follows the chips with one gap")
    list.chipsFooterShown = true
    wait(20)
    compare(H.find(list, "myFooter").visible, true, "shown again")
  }
}
