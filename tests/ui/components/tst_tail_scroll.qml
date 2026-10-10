// tests/ui/components/tst_tail_scroll.qml
// ui/components/TailScroll.qml: a bounded list of model rows that scrolls
// itself, follows its bottom while there, keeps its place and shows Jump ↓
// while scrolled up, hands a wheel to the page at its ends, and is hidden
// with no rows.
import QtQuick
import QtTest
import "../../helpers/find.js" as H
import "../../../ui/components" as UI
import "../../../ui/theme" as T

TestCase {
  id: tc
  name: "TailScroll"
  when: windowShown
  visible: true
  width: 700; height: 600

  // The test delegate's height; init() puts it back to 20.
  property real rowHeight: 20

  T.Theme { id: testTheme }

  // A row exactly tc.rowHeight tall, so content heights are exact.
  Component {
    id: rowC

    Rectangle {
      required property var modelData
      objectName: "tailRow" + modelData
      width: ListView.view ? ListView.view.width : 0
      height: tc.rowHeight
      color: "#444444"
    }
  }

  Component { id: tailC; UI.TailScroll { width: 400 } }

  // A page around the TailScroll: a vertical Flickable over a Column taller
  // than the Flickable, as tst_events_pane.qml builds it.
  Component {
    id: stackC

    Flickable {
      width: 400; height: 400
      contentWidth: width
      contentHeight: column.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      interactive: contentHeight > height

      property alias tail: tailScroll

      Column {
        id: column
        width: parent.width

        Item { width: parent.width; height: 100 }
        UI.TailScroll { id: tailScroll; width: parent.width; theme: testTheme; rowDelegate: rowC; maxHeight: 200 }
        Item { width: parent.width; height: 800 }
      }
    }
  }

  // An owner's Column with spacing and a sibling below the TailScroll.
  Component {
    id: columnC

    Column {
      spacing: 10
      property alias tail: inColumn

      Item { width: 300; height: 40 }
      UI.TailScroll { id: inColumn; width: 300; theme: testTheme; rowDelegate: rowC }
      Item { width: 300; height: 30 }
    }
  }

  // The same Column without the TailScroll.
  Component {
    id: bareColumnC

    Column {
      spacing: 10

      Item { width: 300; height: 40 }
      Item { width: 300; height: 30 }
    }
  }

  function init() { tc.rowHeight = 20 }

  // A TailScroll in testTheme drawing rowC, unless props say otherwise. Props
  // are assigned after creation, in order: createTemporaryObject's property
  // map turns a JS array into a list, and an owner binds real arrays.
  function make(props) {
    var p = { theme: testTheme, rowDelegate: rowC }
    for (var k in props) p[k] = props[k]
    var tail = createTemporaryObject(tailC, tc)
    for (var key in p) tail[key] = p[key]
    wait(30)
    return tail
  }

  function rows(n) {
    var out = []
    for (var i = 1; i <= n; i++) out.push(i)
    return out
  }

  function listOf(tail) { return H.find(tail, "tailList") }
  function jumpOf(tail) { return H.find(tail, "tailJump") }

  function atBottom(list) {
    return Math.abs(list.contentY - (list.originY + list.contentHeight - list.height)) <= 1
  }

  // 50 rows (1000 px) capped at 200, scrolled 300 px below the top: away from the bottom.
  function scrolledUp() {
    var tail = make({ maxHeight: 200, model: rows(50) })
    var list = listOf(tail)
    list.contentY = list.originY + 300
    wait(30)
    return tail
  }

  function wheelOverList(stack, yDelta) {
    var list = listOf(stack.tail)
    var p = list.mapToItem(stack, list.width / 2, list.height / 2)
    mouseWheel(stack, p.x, p.y, 0, yDelta, Qt.NoButton, Qt.NoModifier)
  }

  // ---- layout --------------------------------------------------------------

  // T1
  function test_the_list_height_is_bounded() {
    var short = make({ maxHeight: 300, model: rows(3) })
    var list = listOf(short)
    compare(list.contentHeight, 60)
    compare(list.height, list.contentHeight, "a short list is exactly as tall as its rows")
    verify(list.height < short.maxHeight)
    compare(list.clip, true)
    compare(list.width, short.width, "the list is TailScroll's full width")
    compare(short.following, true)
    compare(jumpOf(short).visible, false)

    var long = make({ maxHeight: 300, model: rows(100) })
    var longList = listOf(long)
    compare(longList.height, 300, "a long list is capped")
    verify(longList.contentHeight > longList.height, "and scrolls inside itself")
    compare(long.implicitHeight, 300, "following, no Jump line in the height")
  }

  // ---- following -----------------------------------------------------------

  // T2
  function test_a_long_model_opens_at_its_bottom() {
    var tail = make({ maxHeight: 200, model: rows(50) })
    var list = listOf(tail)
    verify(list.contentHeight > list.height, "the list scrolls")
    tryVerify(function () { return atBottom(list) }, 1000, "the list opens at its bottom")
    compare(tail.following, true)
  }

  // T3
  function test_a_new_model_at_the_bottom_is_followed() {
    var tail = make({ maxHeight: 200, model: rows(50) })
    var list = listOf(tail)
    tryVerify(function () { return atBottom(list) }, 1000)
    tail.model = rows(52)
    wait(50)
    compare(list.count, 52)
    tryVerify(function () { return atBottom(list) }, 1000, "the newest row is in view")
    compare(tail.following, true)
  }

  // T4
  function test_scrolled_up_it_stays_put_and_shows_jump() {
    var tail = scrolledUp()
    var list = listOf(tail)
    var jump = jumpOf(tail)
    compare(tail.following, false)
    compare(jump.visible, true)
    compare(jump.text, "Jump ↓")
    verify(jump.mapToItem(tail, 0, 0).y >= list.y + list.height, "Jump sits below the list")
    compare(Math.round(jump.x + jump.width), Math.round(jump.parent.width), "at the line's right edge")
    compare(Math.round(jump.parent.width), Math.round(tail.width), "the line is TailScroll's width")
    var before = list.contentY
    tail.model = rows(52)
    wait(50)
    compare(list.count, 52)
    compare(list.contentY, before, "a new model does not move a scrolled-up list")
    compare(tail.following, false)
    compare(jump.visible, true, "a new model does not hide Jump")
  }

  // T5
  function test_jump_returns_to_the_bottom_and_resumes_following() {
    var tail = scrolledUp()
    var list = listOf(tail)
    var jump = jumpOf(tail)
    var withJump = tail.implicitHeight
    verify(withJump > list.height, "the Jump line is in the height")
    mouseClick(jump)
    tryVerify(function () { return atBottom(list) }, 1000, "the bottom is in view")
    compare(tail.following, true)
    compare(jump.visible, false)
    tryVerify(function () { return tail.implicitHeight < withJump }, 1000, "the Jump line leaves the height")
    compare(tail.implicitHeight, list.height)
    tail.model = rows(55)
    wait(50)
    compare(list.count, 55)
    tryVerify(function () { return atBottom(list) }, 1000, "the next model is followed")
  }

  // T6
  function test_calling_jump_does_what_the_click_does() {
    var tail = scrolledUp()
    var list = listOf(tail)
    var withJump = tail.implicitHeight
    tail.jump()
    wait(30)
    verify(atBottom(list), "at the bottom")
    compare(tail.following, true)
    compare(jumpOf(tail).visible, false)
    verify(tail.implicitHeight < withJump, "the Jump line leaves the height")
    tail.model = rows(55)
    wait(50)
    tryVerify(function () { return atBottom(list) }, 1000, "the next model is followed")
  }

  // T7
  function test_scrolling_back_to_the_bottom_resumes_following() {
    var tail = scrolledUp()
    var list = listOf(tail)
    compare(tail.following, false)
    list.positionViewAtEnd()
    wait(30)
    compare(tail.following, true)
    compare(jumpOf(tail).visible, false)
    tail.model = rows(52)
    wait(50)
    tryVerify(function () { return atBottom(list) }, 1000, "the next model is followed")
  }

  // T8
  function test_a_model_that_now_fits_sits_at_its_top_and_follows() {
    var tail = scrolledUp()
    var list = listOf(tail)
    tail.model = rows(3)
    wait(50)
    compare(list.count, 3)
    compare(list.contentY, list.originY, "a list that now fits sits at its top")
    compare(tail.following, true)
    compare(jumpOf(tail).visible, false)
  }

  // T9
  function test_taller_rows_and_a_smaller_cap_keep_a_following_list_at_its_bottom() {
    var tail = make({ maxHeight: 200, model: rows(50) })
    var list = listOf(tail)
    tryVerify(function () { return atBottom(list) }, 1000)
    var tall = list.contentHeight
    tc.rowHeight = 30
    tryVerify(function () { return list.contentHeight > tall }, 1000, "the rows grow")
    tryVerify(function () { return atBottom(list) }, 1000, "the list stays at its bottom")
    compare(tail.following, true)
    tail.maxHeight = 100
    wait(30)
    compare(list.height, 100)
    tryVerify(function () { return atBottom(list) }, 1000, "a smaller cap keeps it at its bottom")
    compare(tail.following, true)
  }

  // T10
  function test_with_no_rows_it_is_hidden_and_following() {
    var empty = make({ maxHeight: 200, model: [] })
    compare(empty.visible, false)
    compare(listOf(empty).visible, false)
    compare(jumpOf(empty).visible, false)
    compare(empty.following, true)

    var tail = scrolledUp()
    var list = listOf(tail)
    compare(tail.following, false)
    tail.model = []
    wait(50)
    compare(list.count, 0)
    compare(tail.visible, false)
    compare(list.visible, false)
    compare(jumpOf(tail).visible, false)
    compare(tail.following, true, "an empty list is at its bottom")
    tail.model = rows(50)
    wait(50)
    compare(tail.visible, true)
    tryVerify(function () { return atBottom(list) }, 1000, "the rows come back at the bottom")
  }

  // T11
  function test_object_names() {
    var named = make({ model: rows(3) })
    compare(named.objectName, "tailScroll")
    verify(H.find(named, "tailList") !== null, "the default list name")
    verify(H.find(named, "tailJump") !== null, "the default Jump name")
    verify(H.find(named, "tailRow1") !== null, "rows come from rowDelegate")

    var renamed = make({ listName: "x", jumpName: "y", model: rows(3) })
    verify(H.find(renamed, "x") !== null, "listName names the list")
    verify(H.find(renamed, "y") !== null, "jumpName names the Jump button")
    compare(H.find(renamed, "tailList"), null)
    compare(H.find(renamed, "tailJump"), null)
  }

  // ---- wheel hand-off (T12) ------------------------------------------------

  function test_a_wheel_up_from_the_bottom_scrolls_the_list() {
    var stack = createTemporaryObject(stackC, tc)
    stack.tail.model = rows(50)
    wait(50)
    var list = listOf(stack.tail)
    verify(atBottom(list), "the list opens at its bottom")
    wheelOverList(stack, 120)
    tryVerify(function () { return !stack.tail.following }, 1000, "the wheel leaves the bottom")
    compare(stack.contentY, 0, "the page does not move")
  }

  function test_a_wheel_down_at_the_bottom_scrolls_the_page() {
    var stack = createTemporaryObject(stackC, tc)
    stack.tail.model = rows(50)
    wait(50)
    var list = listOf(stack.tail)
    list.positionViewAtEnd()
    wait(30)
    verify(list.atYEnd, "the list starts at its bottom")
    var before = list.contentY
    wheelOverList(stack, -120)
    tryVerify(function () { return stack.contentY > 0 }, 1000, "the page scrolls down")
    compare(list.contentY, before, "the list stays at its bottom")
  }

  function test_a_wheel_over_a_list_that_fits_scrolls_the_page() {
    var stack = createTemporaryObject(stackC, tc)
    stack.tail.model = rows(3)
    wait(50)
    var list = listOf(stack.tail)
    verify(list.contentHeight <= list.height, "the rows fit")
    wheelOverList(stack, -120)
    tryVerify(function () { return stack.contentY > 0 }, 1000, "the page scrolls down")
  }

  // T13
  function test_an_empty_tail_scroll_takes_no_room_in_a_column() {
    var column = createTemporaryObject(columnC, tc)
    var bare = createTemporaryObject(bareColumnC, tc)
    wait(30)
    compare(bare.implicitHeight, 80)
    compare(column.implicitHeight, bare.implicitHeight, "neither height nor spacing")
    column.tail.model = rows(3)
    wait(30)
    compare(column.implicitHeight, 80 + 10 + 60, "with rows it takes its height and one spacing")
  }

  // T14
  function test_destroying_it_while_a_model_arrives_warns_nothing() {
    failOnWarning(/TypeError|ReferenceError|is not a function/)
    var tail = make({ maxHeight: 200, model: rows(50) })
    tail.model = rows(52)
    tail.destroy()
    wait(50)
  }

  // ---- Review Focus --------------------------------------------------------

  // Review Focus 1
  function test_a_taller_cap_that_fits_the_rows_shows_them_all_and_follows() {
    var tail = scrolledUp()
    var list = listOf(tail)
    compare(tail.following, false)
    tail.maxHeight = 2000
    wait(30)
    compare(list.height, list.contentHeight, "the rows fit")
    compare(list.contentY, list.originY, "every row is in view")
    compare(tail.following, true)
    compare(jumpOf(tail).visible, false)
  }

  // Review Focus 2
  function test_an_integer_model_is_shown_and_followed() {
    var tail = make({ maxHeight: 200, model: 30 })
    var list = listOf(tail)
    compare(list.count, 30)
    compare(tail.visible, true)
    verify(list.contentHeight > list.height, "the list scrolls")
    tryVerify(function () { return atBottom(list) }, 1000, "at its bottom")
    compare(tail.following, true)
  }

  // Review Focus 3
  function test_the_same_rows_as_a_new_array_keep_a_scrolled_up_list_put() {
    var tail = scrolledUp()
    var list = listOf(tail)
    var before = list.contentY
    tail.model = rows(50)
    wait(50)
    compare(list.count, 50)
    compare(list.contentY, before)
    compare(tail.following, false)
    compare(jumpOf(tail).visible, true)
  }

  // Review Focus 4
  function test_a_list_scrolled_to_its_top_stays_there_through_a_new_model() {
    var tail = make({ maxHeight: 200, model: rows(50) })
    var list = listOf(tail)
    list.positionViewAtBeginning()
    wait(30)
    compare(list.contentY, list.originY)
    compare(tail.following, false, "the top of a list that scrolls is not its bottom")
    tail.model = rows(52)
    wait(50)
    compare(list.count, 52)
    compare(list.contentY, list.originY, "still at its top")
    compare(tail.following, false)
    compare(jumpOf(tail).visible, true)
  }

  // Review Focus 5
  function test_without_a_theme_jump_uses_the_fallback_palette() {
    failOnWarning(/TypeError|ReferenceError|is not a function/)
    var tail = make({ theme: null, maxHeight: 200, model: rows(50) })
    var list = listOf(tail)
    list.contentY = list.originY + 300
    wait(30)
    verify(tail.palette !== null && tail.palette !== undefined, "the fallback palette")
    compare(jumpOf(tail).visible, true)
    verify(jumpOf(tail).theme === tail.palette, "Jump draws in it")
  }
}
