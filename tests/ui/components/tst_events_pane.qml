// tests/ui/components/tst_events_pane.qml
// ui/components/EventsPane.qml: a run's event rows from props (time, glyph,
// label, status, duration, a phase's detail under it), the All / Phases /
// Failures chips, "… N earlier events", the loading / empty / filtered-empty
// line, the error block, a bounded list that scrolls itself and hands a wheel
// to the page at its ends, and attemptRequested for a row naming an attempt.
// The list follows the newest row while it is at its bottom; Jump ↓ under a
// list that is not following returns it there.
import QtQuick
import QtTest
import "../../helpers/find.js" as H
import "../../../ui/components" as UI
import "../../../ui/components/runGlyphs.js" as RG
import "../../../ui/theme" as T

TestCase {
  id: tc
  name: "EventsPane"
  when: windowShown
  visible: true
  width: 700; height: 600

  // Three distinct tokens, so a tint can only match the one it is meant to.
  T.Theme { id: testTheme; foreground: "#eeeeee"; dim: "#777777"; urgent: "#ff3300" }

  Component { id: paneC; UI.EventsPane { width: 600 } }

  // The panel's own page around the pane: a vertical Flickable over a Column,
  // taller than the Flickable, as tst_graph_wheel.qml builds it.
  Component {
    id: stackC

    Flickable {
      width: 600; height: 400
      contentWidth: width
      contentHeight: column.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      interactive: contentHeight > height

      property alias pane: eventsPane

      Column {
        id: column
        width: parent.width

        Item { width: parent.width; height: 100 }
        UI.EventsPane { id: eventsPane; width: parent.width; theme: testTheme; maxListHeight: 200 }
        Item { width: parent.width; height: 800 }
      }
    }
  }

  SignalSpy { id: filterSpy; signalName: "filterRequested" }
  SignalSpy { id: attemptSpy; signalName: "attemptRequested" }

  // A pane in testTheme unless props names a theme (null included). Props are
  // assigned after creation: createTemporaryObject's property map turns a JS
  // array into a list that Array.isArray rejects, and an owner binds real arrays.
  function make(props) {
    var p = props || {}
    if (!("theme" in p)) p.theme = testTheme
    var pane = createTemporaryObject(paneC, tc)
    for (var key in p) pane[key] = p[key]
    filterSpy.target = pane
    filterSpy.clear()
    attemptSpy.target = pane
    attemptSpy.clear()
    wait(30)
    return pane
  }

  // A complete row as RunEvents.eventRow returns it; `fields` overrides.
  function eventRow(seq, fields) {
    var row = { seq: seq, time: "12:00:00", level: "attempt", label: "row " + seq, status: "done",
                glyph: "done", duration: "", detail: "", card: "card-" + seq, phase: "implement",
                attempt: 1 }
    for (var key in fields) row[key] = fields[key]
    return row
  }

  function manyRows(n) {
    var rows = []
    for (var i = 1; i <= n; i++) rows.push(eventRow(i, {}))
    return rows
  }

  function rowOf(pane, seq) { return H.find(pane, "eventsRow" + seq) }
  function part(pane, seq, name) { return H.find(rowOf(pane, seq), name) }
  function listOf(pane) { return H.find(pane, "eventsList") }
  function statusOf(pane) { return H.find(pane, "eventsStatus") }

  function wheelOverList(stack, yDelta) {
    var list = listOf(stack.pane)
    var p = list.mapToItem(stack, list.width / 2, list.height / 2)
    mouseWheel(stack, p.x, p.y, 0, yDelta, Qt.NoButton, Qt.NoModifier)
  }

  // ---- rows ----------------------------------------------------------------

  function test_rows_render_time_glyph_label_status_duration() {
    var pane = make({ rows: [
      eventRow(4, { time: "12:01:05", level: "attempt", label: "Card A implement.2", status: "done",
                    glyph: "done", duration: "4.2s", card: "card-a", phase: "implement", attempt: 2 }),
      eventRow(7, { time: "12:01:09", level: "phase", label: "Card A verify", status: "started",
                    glyph: "running", duration: "", card: "card-a", phase: "verify", attempt: 0 })
    ] })
    compare(listOf(pane).count, 2)
    compare(part(pane, 4, "eventsRowTime").text, "12:01:05")
    compare(part(pane, 4, "eventsRowGlyph").text, RG.glyphOf("done"))
    compare(part(pane, 4, "eventsRowLabel").text, "Card A implement.2")
    compare(part(pane, 4, "eventsRowStatus").text, "done")
    compare(part(pane, 4, "eventsRowDuration").text, "4.2s")
    compare(part(pane, 7, "eventsRowTime").text, "12:01:09")
    compare(part(pane, 7, "eventsRowGlyph").text, RG.glyphOf("running"))
    compare(part(pane, 7, "eventsRowLabel").text, "Card A verify")
    compare(part(pane, 7, "eventsRowStatus").text, "started")
    compare(part(pane, 7, "eventsRowDuration").text, "", "an empty part is drawn empty")
    verify(rowOf(pane, 4).y < rowOf(pane, 7).y, "input order: the newest row at the bottom")
    compare(rowOf(pane, 4).index, -1, "rows are not keyboard-navigable")
    verify(Qt.colorEqual(part(pane, 4, "eventsRowTime").color, testTheme.dim), "the time is dim")
    verify(Qt.colorEqual(part(pane, 4, "eventsRowDuration").color, testTheme.dim), "the duration is dim")
  }

  function test_row_text_is_plain() {
    var pane = make({ rows: [eventRow(1, { label: "<b>x</b>" })] })
    var label = part(pane, 1, "eventsRowLabel")
    compare(label.textFormat, Text.PlainText, "a label is never read as markup")
    compare(label.text, "<b>x</b>")
  }

  function test_a_failed_phase_shows_its_detail_under_the_row() {
    var pane = make({ rows: [
      eventRow(1, { level: "phase", status: "failed", glyph: "dead", attempt: 0,
                    detail: "gate failed: pytest exited 1" }),
      eventRow(2, { level: "phase", status: "done", attempt: 0, detail: "" })
    ] })
    var detail = part(pane, 1, "eventsRowDetail")
    compare(detail.visible, true)
    compare(detail.text, "gate failed: pytest exited 1")
    compare(detail.wrapMode, Text.WordWrap)
    verify(Qt.colorEqual(detail.color, testTheme.urgent), "a failure's detail is urgent")
    verify(detail.y > part(pane, 1, "eventsRowLabel").y, "the detail sits under the row")
    compare(part(pane, 2, "eventsRowDetail").visible, false, "no detail, no second line")

    var plain = make({ rows: [eventRow(3, { level: "phase", status: "done", attempt: 0, detail: "note" })] })
    verify(Qt.colorEqual(part(plain, 3, "eventsRowDetail").color, testTheme.dim), "a non-failure detail is dim")
  }

  function test_failure_rows_use_urgent_and_the_double_bang() {
    var failures = ["failed", "escalated", "gate_failed", "schema_invalid", "harness_error"]
    var levels = ["attempt", "story", "phase", "subtask", "run"]
    var rows = []
    for (var i = 0; i < failures.length; i++)
      rows.push(eventRow(i + 1, { level: levels[i], status: failures[i], glyph: "dead" }))
    rows.push(eventRow(9, { level: "story", status: "done", glyph: "done", detail: "fine" }))
    var pane = make({ rows: rows })
    for (var j = 0; j < failures.length; j++) {
      compare(part(pane, j + 1, "eventsRowGlyph").text, RG.GLYPHS.escalated, failures[j] + " at level " + levels[j] + " shows ‼")
      var parts = ["eventsRowGlyph", "eventsRowLabel", "eventsRowStatus"]
      for (var k = 0; k < parts.length; k++)
        verify(Qt.colorEqual(part(pane, j + 1, parts[k]).color, testTheme.urgent), failures[j] + " " + parts[k])
    }
    compare(part(pane, 9, "eventsRowGlyph").text, RG.GLYPHS.done)
    var all = ["eventsRowTime", "eventsRowGlyph", "eventsRowLabel", "eventsRowStatus",
               "eventsRowDuration", "eventsRowDetail"]
    for (var m = 0; m < all.length; m++)
      verify(!Qt.colorEqual(part(pane, 9, all[m]).color, testTheme.urgent), "done " + all[m] + " is not urgent")
  }

  function test_unknown_glyph_key_shows_no_glyph() {
    var keys = ["bogus", "", "constructor", "__proto__"]
    var rows = []
    for (var i = 0; i < keys.length; i++) rows.push(eventRow(i + 1, { status: "", glyph: keys[i] }))
    var pane = make({ rows: rows })
    for (var j = 0; j < keys.length; j++)
      compare(part(pane, j + 1, "eventsRowGlyph").text, "", "glyph key " + JSON.stringify(keys[j]))
  }

  function test_garbage_props_render_without_warnings() {
    var pane = make({ theme: null, rows: [
      null, 5, "x", [],
      { seq: 1, time: 5, label: null, status: 7, duration: {}, detail: [], card: 3, phase: null,
        attempt: "2", glyph: "constructor" },
      { seq: 2 },
      { seq: 3, glyph: "__proto__", card: "c", phase: "p", attempt: -1 }
    ] })
    verify(pane.palette, "falls back to its own Theme")
    compare(listOf(pane).count, 3, "entries that are not objects are skipped")
    var parts = ["eventsRowTime", "eventsRowGlyph", "eventsRowLabel", "eventsRowStatus", "eventsRowDuration"]
    for (var s = 1; s <= 3; s++)
      for (var i = 0; i < parts.length; i++)
        compare(part(pane, s, parts[i]).text, "", "row " + s + " " + parts[i] + " is drawn empty")
    compare(part(pane, 1, "eventsRowDetail").visible, false)
    verify(Qt.colorEqual(part(pane, 2, "eventsRowLabel").color, pane.palette.foreground))
    pane.theme = testTheme
    pane.theme = null
    wait(30)
    verify(pane.palette, "back to its own Theme when the owner's goes away")
  }

  // ---- clicks --------------------------------------------------------------

  function test_a_row_naming_an_attempt_emits_attemptRequested() {
    var pane = make({ rows: [eventRow(5, { card: "card-a", phase: "implement", attempt: 2 })] })
    compare(rowOf(pane, 5).hoverCursorShape, Qt.PointingHandCursor)
    mouseClick(rowOf(pane, 5))
    compare(attemptSpy.count, 1)
    compare(attemptSpy.signalArguments[0][0], "card-a")
    compare(attemptSpy.signalArguments[0][1], "implement")
    compare(attemptSpy.signalArguments[0][2], 2)
  }

  function test_a_row_without_an_attempt_emits_nothing() {
    var pane = make({ rows: [
      eventRow(1, { level: "phase", attempt: 0 }),
      eventRow(2, { card: "" }),
      eventRow(3, { phase: "" }),
      eventRow(4, { attempt: "2" }),
      eventRow(5, { level: "run", card: "", phase: "", attempt: 0, label: "run started", status: "started" })
    ] })
    for (var s = 1; s <= 5; s++) {
      compare(rowOf(pane, s).hoverCursorShape, Qt.ArrowCursor, "row " + s + " has the arrow")
      mouseClick(rowOf(pane, s))
      compare(attemptSpy.count, 0, "row " + s + " emits nothing")
    }
  }

  // ---- filter chips --------------------------------------------------------

  function mixedRows() {
    return [
      eventRow(1, { level: "run", label: "run started", status: "started", card: "", phase: "", attempt: 0 }),
      eventRow(2, { level: "story", label: "Story", status: "escalated", card: "", phase: "", attempt: 0 }),
      eventRow(3, { level: "phase", status: "done", attempt: 0 }),
      eventRow(4, { level: "attempt", status: "done" }),
      eventRow(5, { level: "attempt", status: "failed" })
    ]
  }

  function seqsOf(pane) { return pane.shownRows.map(function (r) { return r.seq }) }

  function test_filter_chips_mark_the_active_filter() {
    var ids = ["All", "Phases", "Failures"]
    for (var i = 0; i < ids.length; i++) {
      var pane = make({ rows: mixedRows(), filter: ids[i] })
      for (var j = 0; j < ids.length; j++) {
        var chip = H.find(pane, "eventsFilterChip" + ids[j])
        verify(chip, ids[j] + " chip exists")
        compare(chip.text, ids[j], "a chip shows its label and no count")
        compare(chip.active, i === j, "filter " + ids[i] + ": chip " + ids[j])
      }
    }
    var chips = make({ rows: [] })
    verify(H.find(chips, "eventsFilterChipAll").x < H.find(chips, "eventsFilterChipPhases").x, "All, then Phases")
    verify(H.find(chips, "eventsFilterChipPhases").x < H.find(chips, "eventsFilterChipFailures").x, "then Failures")
    var odd = make({ rows: mixedRows(), filter: "Bogus" })
    for (var k = 0; k < ids.length; k++)
      compare(H.find(odd, "eventsFilterChip" + ids[k]).active, false, "an unknown filter marks no chip")
    compare(listOf(odd).count, 5, "an unknown filter shows every row")
  }

  function test_a_chip_click_requests_its_filter_without_changing_it() {
    var pane = make({ rows: mixedRows() })
    mouseClick(H.find(pane, "eventsFilterChipFailures"))
    compare(filterSpy.count, 1)
    compare(filterSpy.signalArguments[0][0], "Failures")
    compare(pane.filter, "All", "the pane never assigns its filter")
    compare(listOf(pane).count, 5, "the rows shown are unchanged")
    mouseClick(H.find(pane, "eventsFilterChipAll"))
    compare(filterSpy.count, 2, "the active chip emits too")
    compare(filterSpy.signalArguments[1][0], "All")
  }

  function test_the_pane_applies_the_filter() {
    var pane = make({ rows: mixedRows() })
    compare(seqsOf(pane), [1, 2, 3, 4, 5])
    pane.filter = "Phases"
    wait(30)
    compare(seqsOf(pane), [3, 4, 5])
    compare(listOf(pane).count, 3)
    verify(!rowOf(pane, 1), "the run row is not drawn under Phases")
    pane.filter = "Failures"
    wait(30)
    compare(seqsOf(pane), [2, 5], "a failure at any level")
    compare(listOf(pane).count, 2)
  }

  // ---- earlier events and the status line ----------------------------------

  function test_earlier_line_shows_the_dropped_count() {
    compare(H.find(make({ rows: mixedRows(), dropped: 0 }), "eventsEarlier").visible, false)
    compare(H.find(make({ rows: mixedRows(), dropped: -1 }), "eventsEarlier").visible, false)
    var one = H.find(make({ rows: mixedRows(), dropped: 1 }), "eventsEarlier")
    compare(one.visible, true)
    compare(one.text, "… 1 earlier event")
    var many = make({ rows: mixedRows(), dropped: 37 })
    compare(H.find(many, "eventsEarlier").text, "… 37 earlier events")
    verify(Qt.colorEqual(H.find(many, "eventsEarlier").color, testTheme.dim))
    verify(H.find(many, "eventsEarlier").y < listOf(many).y, "above the list")
    many.filter = "Failures"
    wait(30)
    compare(H.find(many, "eventsEarlier").visible, true, "independent of the filter")
    compare(H.find(many, "eventsEarlier").text, "… 37 earlier events")
  }

  function test_empty_state_says_no_events_yet() {
    var pane = make({ rows: [], status: "ok" })
    compare(statusOf(pane).visible, true)
    compare(statusOf(pane).text, "No events yet.")
    compare(listOf(pane).visible, false)
    compare(statusOf(make({ rows: [] })).text, "No events yet.", "idle too")

    var bad = [null, undefined, "x", 5, {}]
    var labels = ["null", "undefined", "\"x\"", "5", "{}"]
    for (var i = 0; i < bad.length; i++) {
      var shown = make({ rows: mixedRows(), status: "ok" })
      compare(listOf(shown).visible, true, labels[i] + " starts with rows")
      compare(statusOf(shown).visible, false, labels[i] + " starts with no status line")
      shown.rows = bad[i]
      wait(30)
      compare(shown.shownRows.length, 0, labels[i])
      compare(statusOf(shown).text, "No events yet.", labels[i] + " reads as empty")
      compare(listOf(shown).visible, false, labels[i] + " hides the list")
    }
  }

  function test_a_filter_that_empties_the_list_says_so() {
    var pane = make({ rows: [eventRow(1, { status: "done" })], filter: "Failures", status: "ok" })
    compare(statusOf(pane).text, "No events match the filter.")
    compare(listOf(pane).visible, false)
  }

  function test_loading_without_rows_shows_loading_and_with_rows_keeps_them() {
    var empty = make({ rows: [], status: "loading" })
    compare(statusOf(empty).text, "Loading events…")
    compare(statusOf(empty).visible, true)
    var held = make({ rows: mixedRows(), status: "loading" })
    compare(statusOf(held).visible, false, "no loading line over held rows")
    compare(listOf(held).visible, true)
    compare(listOf(held).count, 5)
  }

  // ---- error state ---------------------------------------------------------

  function test_error_state_shows_the_headline_and_keeps_the_rows() {
    var pane = make({ rows: mixedRows(), status: "error" })
    var block = H.find(pane, "eventsError")
    compare(block.visible, true)
    compare(H.find(pane, "eventsErrorText").text, "Events unreadable.")
    verify(Qt.colorEqual(H.find(pane, "eventsErrorText").color, testTheme.urgent))
    compare(listOf(pane).visible, true, "the rows held stay")
    compare(listOf(pane).count, 5)
    verify(block.y < listOf(pane).y, "the error sits above the rows")
    pane.errorText = "events unreadable"
    compare(H.find(pane, "eventsErrorText").text, "events unreadable")

    var states = ["idle", "loading", "ok"]
    for (var i = 0; i < states.length; i++) {
      pane.status = states[i]
      compare(H.find(pane, "eventsError").visible, false, "no error block while " + states[i])
    }

    var bare = make({ rows: [], status: "error" })
    compare(H.find(bare, "eventsError").visible, true)
    compare(statusOf(bare).visible, false, "an error with no rows does not say No events yet.")

    var narrowed = make({ rows: [eventRow(1, { status: "done" })], filter: "Failures", status: "error" })
    compare(H.find(narrowed, "eventsError").visible, true)
    compare(statusOf(narrowed).text, "No events match the filter.", "rows held but filtered out")
  }

  function test_the_raw_message_is_one_click_away() {
    var pane = make({ rows: mixedRows(), status: "error", errorMessage: "am events: exit 3: bad journal" })
    var toggle = H.find(pane, "eventsErrorToggle")
    var message = H.find(pane, "eventsErrorMessage")
    compare(toggle.visible, true)
    compare(toggle.text, "Details")
    compare(message.visible, false, "hidden at first")
    mouseClick(toggle)
    compare(message.visible, true)
    compare(message.text, "am events: exit 3: bad journal")
    compare(message.textFormat, Text.PlainText)
    compare(message.wrapMode, Text.WordWrap)
    compare(toggle.text, "Hide")
    mouseClick(toggle)
    compare(message.visible, false)
    compare(toggle.text, "Details")

    mouseClick(toggle)
    compare(message.visible, true)
    pane.status = "ok"
    pane.status = "error"
    compare(message.visible, false, "the next error starts collapsed")
    compare(toggle.text, "Details")

    var quiet = make({ rows: [], status: "error", errorMessage: "" })
    compare(H.find(quiet, "eventsErrorToggle").visible, false, "no message, no toggle")
    compare(H.find(quiet, "eventsErrorMessage").visible, false)
  }

  // ---- the list: bounded height, own scrolling, wheel hand-off -------------

  function test_the_list_height_is_bounded() {
    var short = make({ rows: manyRows(3), maxListHeight: 300 })
    var list = listOf(short)
    verify(list.contentHeight > 0)
    compare(list.height, list.contentHeight, "a short list is exactly as tall as its rows")
    verify(list.height < short.maxListHeight)
    compare(list.clip, true)

    var long = make({ rows: manyRows(100), maxListHeight: 300 })
    var longList = listOf(long)
    compare(longList.height, 300, "a long list is capped")
    verify(longList.contentHeight > longList.height, "and scrolls inside itself")
    verify(long.implicitHeight >= longList.height, "the pane holds the capped list")
  }

  function test_a_wheel_in_the_middle_of_the_list_scrolls_only_the_list() {
    var stack = createTemporaryObject(stackC, tc)
    stack.pane.rows = manyRows(50)
    wait(50)
    var list = listOf(stack.pane)
    list.contentY = list.originY + 100
    wait(30)
    verify(!list.atYBeginning && !list.atYEnd, "the list starts in its middle")
    var before = list.contentY
    wheelOverList(stack, -120)
    tryVerify(function () { return list.contentY > before }, 1000, "the list scrolls down")
    compare(stack.contentY, 0, "the page does not move")
  }

  function test_a_wheel_down_at_the_list_bottom_scrolls_the_page() {
    var stack = createTemporaryObject(stackC, tc)
    stack.pane.rows = manyRows(50)
    wait(50)
    var list = listOf(stack.pane)
    list.positionViewAtEnd()
    wait(30)
    verify(list.atYEnd, "the list starts at its bottom")
    var before = list.contentY
    wheelOverList(stack, -120)
    tryVerify(function () { return stack.contentY > 0 }, 1000, "the page scrolls down")
    compare(list.contentY, before, "the list stays at its bottom")
  }

  function test_a_wheel_up_at_the_list_top_scrolls_the_page() {
    var stack = createTemporaryObject(stackC, tc)
    stack.pane.rows = manyRows(50)
    wait(50)
    stack.contentY = 50
    var list = listOf(stack.pane)
    list.positionViewAtBeginning()
    wait(30)
    verify(list.atYBeginning, "the list starts at its top")
    wheelOverList(stack, 120)
    tryVerify(function () { return stack.contentY < 50 }, 1000, "the page scrolls up")
    verify(list.atYBeginning, "the list stays at its top")
  }

  function test_a_wheel_over_a_list_that_fits_scrolls_the_page() {
    var stack = createTemporaryObject(stackC, tc)
    stack.pane.rows = manyRows(3)
    wait(50)
    var list = listOf(stack.pane)
    verify(list.contentHeight <= list.height, "the rows fit")
    wheelOverList(stack, -120)
    tryVerify(function () { return stack.contentY > 0 }, 1000, "the page scrolls down")
  }

  function test_new_rows_keep_the_list_where_it_was() {
    var pane = make({ rows: manyRows(50), maxListHeight: 200 })
    var list = listOf(pane)
    list.contentY = list.originY + 300
    wait(30)
    var before = list.contentY
    pane.rows = manyRows(52)
    wait(50)
    compare(list.count, 52, "the new rows are shown")
    compare(list.contentY, before, "a new rows array does not move the list")
    pane.rows = manyRows(3)
    wait(50)
    compare(list.count, 3)
    compare(list.contentY, list.originY, "a list that now fits sits at its top")
  }

  // ---- following the newest row --------------------------------------------

  function atBottom(list) {
    return Math.abs(list.contentY - (list.originY + list.contentHeight - list.height)) <= 1
  }

  // A pane of 50 rows whose list is scrolled 300 px below its top, away from its bottom.
  function scrolledUp() {
    var pane = make({ rows: manyRows(50), maxListHeight: 200 })
    var list = listOf(pane)
    list.contentY = list.originY + 300
    wait(30)
    return pane
  }

  // n rows where every 4th is a story row: Phases drops those, and still scrolls.
  function storyAndPhaseRows(n) {
    var rows = []
    for (var i = 1; i <= n; i++)
      rows.push(eventRow(i, i % 4 === 0 ? { level: "story", card: "", phase: "", attempt: 0 } : {}))
    return rows
  }

  function test_a_long_list_opens_at_its_newest_row() {
    var pane = make({ rows: manyRows(50), maxListHeight: 200 })
    var list = listOf(pane)
    verify(list.contentHeight > list.height, "the list scrolls")
    tryVerify(function () { return atBottom(list) }, 1000, "the list opens at its bottom")
    compare(pane.following, true)
  }

  function test_appending_while_at_the_bottom_follows() {
    var pane = make({ rows: manyRows(50), maxListHeight: 200 })
    var list = listOf(pane)
    pane.rows = manyRows(52)
    wait(50)
    compare(list.count, 52)
    tryVerify(function () { return atBottom(list) }, 1000, "the newest row is in view")
    compare(pane.following, true)
  }

  function test_scrolling_up_stops_following_and_new_rows_do_not_move_the_list() {
    var pane = scrolledUp()
    var list = listOf(pane)
    compare(pane.following, false)
    var before = list.contentY
    pane.rows = manyRows(52)
    wait(50)
    compare(list.count, 52)
    compare(list.contentY, before, "the list does not move toward the new rows")
    compare(pane.following, false)
  }

  function test_scrolling_back_to_the_bottom_resumes_following() {
    var pane = scrolledUp()
    var list = listOf(pane)
    compare(pane.following, false)
    list.positionViewAtEnd()
    wait(30)
    compare(pane.following, true)
    pane.rows = manyRows(52)
    wait(50)
    tryVerify(function () { return atBottom(list) }, 1000, "the append is followed")
  }

  function test_a_wheel_up_from_the_bottom_stops_following() {
    var stack = createTemporaryObject(stackC, tc)
    stack.pane.rows = manyRows(50)
    wait(50)
    verify(atBottom(listOf(stack.pane)), "the list opens at its bottom")
    wheelOverList(stack, 120)
    tryVerify(function () { return !stack.pane.following }, 1000, "the wheel leaves the bottom")
    compare(stack.contentY, 0, "the page does not move")
  }

  function test_a_filter_change_keeps_following() {
    var pane = make({ rows: storyAndPhaseRows(60), maxListHeight: 200 })
    var list = listOf(pane)
    tryVerify(function () { return atBottom(list) }, 1000)
    pane.filter = "Phases"
    wait(50)
    compare(list.count, 45)
    verify(list.contentHeight > list.height, "the Phases list scrolls")
    tryVerify(function () { return atBottom(list) }, 1000, "the filtered list is at its bottom")
    compare(pane.following, true)
    pane.rows = storyAndPhaseRows(63)
    wait(50)
    compare(list.count, 48)
    tryVerify(function () { return atBottom(list) }, 1000, "the append is followed")
  }

  function test_a_filter_change_keeps_a_scrolled_up_list_scrolled_up() {
    var pane = make({ rows: storyAndPhaseRows(60), maxListHeight: 200 })
    var list = listOf(pane)
    list.contentY = list.originY + 100
    wait(30)
    compare(pane.following, false)
    var before = list.contentY
    pane.filter = "Phases"
    wait(50)
    compare(list.count, 45)
    compare(pane.following, false)
    compare(list.contentY, before, "the list keeps its contentY")
    pane.filter = "All"
    wait(50)
    compare(pane.following, false, "the filter never resets to following")
  }

  function test_rows_filtered_out_while_scrolled_up_come_back_at_the_bottom() {
    var pane = scrolledUp()
    var list = listOf(pane)
    pane.filter = "Failures"
    wait(50)
    compare(list.visible, false)
    compare(pane.following, true, "an empty list is at its bottom")
    pane.filter = "All"
    wait(50)
    tryVerify(function () { return atBottom(list) }, 1000, "the rows come back at the bottom")
  }

  function test_rows_with_detail_lines_follow_to_the_true_bottom() {
    function detailed(n) {
      var rows = []
      for (var i = 1; i <= n; i++)
        rows.push(eventRow(i, i % 3 === 0 ? { detail: "line one of a long reason\nline two\nline three" } : {}))
      return rows
    }
    var pane = make({ rows: detailed(50), maxListHeight: 200 })
    var list = listOf(pane)
    pane.rows = detailed(52)
    wait(50)
    tryVerify(function () {
      var last = rowOf(pane, 52)
      return last && Math.abs(last.mapToItem(list, 0, last.height).y - list.height) <= 1
    }, 1000, "the last row's bottom edge is the list's bottom edge")
    compare(pane.following, true)
  }

  function test_rows_that_rewrap_taller_keep_a_following_list_at_its_bottom() {
    var rows = []
    for (var i = 1; i <= 30; i++)
      rows.push(eventRow(i, { detail: "a reason long enough to wrap onto more lines once the pane narrows" }))
    var pane = make({ rows: rows, maxListHeight: 200 })
    var list = listOf(pane)
    tryVerify(function () { return atBottom(list) }, 1000)
    var tall = list.contentHeight
    pane.width = 120
    tryVerify(function () { return list.contentHeight > tall }, 1000, "the rows rewrap taller")
    tryVerify(function () { return atBottom(list) }, 1000, "the list stays at its bottom")
    compare(pane.following, true)
  }

  function test_destroying_the_pane_while_rows_arrive_warns_nothing() {
    failOnWarning(/TypeError|ReferenceError|is not a function/)
    var pane = make({ rows: manyRows(50), maxListHeight: 200 })
    pane.rows = manyRows(52)
    pane.destroy()
    wait(50)
  }

  // ---- Jump ----------------------------------------------------------------

  function jumpOf(pane) { return H.find(pane, "eventsJump") }

  function test_jump_shows_while_scrolled_up_and_stays_through_new_rows() {
    var pane = scrolledUp()
    var list = listOf(pane)
    var jump = jumpOf(pane)
    compare(jump.visible, true)
    compare(jump.text, "Jump ↓")
    verify(jump.mapToItem(pane, 0, 0).y >= list.y + list.height, "Jump sits below the list")
    compare(Math.round(jump.x + jump.width), Math.round(jump.parent.width), "at the line's right edge")
    pane.rows = manyRows(52)
    wait(50)
    compare(jump.visible, true, "new rows do not hide it")
  }

  function test_jump_returns_to_the_bottom_and_resumes_following() {
    var pane = scrolledUp()
    var list = listOf(pane)
    var jump = jumpOf(pane)
    var withJump = pane.implicitHeight
    mouseClick(jump)
    tryVerify(function () { return atBottom(list) }, 1000, "the newest row is in view")
    compare(pane.following, true)
    compare(jump.visible, false)
    tryVerify(function () { return pane.implicitHeight < withJump }, 1000, "the Jump line is gone from the pane's height")
    compare(filterSpy.count, 0)
    compare(attemptSpy.count, 0)
    pane.rows = manyRows(55)
    wait(50)
    compare(list.count, 55)
    tryVerify(function () { return atBottom(list) }, 1000, "the append is followed")
  }

  function test_jump_shows_exactly_while_a_list_that_scrolls_is_not_following() {
    var stack = createTemporaryObject(stackC, tc)
    var pane = stack.pane
    pane.rows = manyRows(50)
    wait(50)
    var list = listOf(pane)
    compare(jumpOf(pane).visible, false, "hidden at the bottom")
    wheelOverList(stack, 120)
    tryVerify(function () { return !pane.following }, 1000)
    compare(jumpOf(pane).visible, true, "shown once a wheel leaves the bottom")
    compare(stack.contentY, 0, "the page does not move")
    pane.filter = "Phases"
    wait(50)
    compare(jumpOf(pane).visible, true, "a filter change keeps it")
    list.positionViewAtEnd()
    wait(30)
    compare(jumpOf(pane).visible, false, "hidden once scrolled back to the bottom")
    list.contentY = list.originY + 100
    wait(30)
    compare(jumpOf(pane).visible, true)
    pane.filter = "Failures"
    wait(50)
    compare(jumpOf(pane).visible, false, "no list, no Jump")
    pane.filter = "All"
    wait(50)
    compare(jumpOf(pane).visible, false, "the rows come back at the bottom")
  }

  function test_a_list_that_fits_shows_no_jump() {
    var pane = make({ rows: manyRows(3), maxListHeight: 200 })
    compare(jumpOf(pane).visible, false)
    compare(pane.following, true)
    pane.rows = manyRows(4)
    wait(50)
    compare(jumpOf(pane).visible, false)
    compare(pane.following, true)
  }

  function test_empty_or_garbage_rows_show_no_jump_and_follow() {
    var bad = [[], null, "x"]
    for (var i = 0; i < bad.length; i++) {
      var pane = make({ rows: bad[i], maxListHeight: 200 })
      compare(jumpOf(pane).visible, false, JSON.stringify(bad[i]))
      compare(pane.following, true, JSON.stringify(bad[i]))
    }
  }
}
