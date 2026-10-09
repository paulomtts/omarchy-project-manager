// tests/ui/components/tst_events_pane.qml
// ui/components/EventsPane.qml: a run's event rows from props (time, glyph,
// label, status, duration, a phase's detail under it), the All / Phases /
// Failures chips, "… N earlier events", the loading / empty / filtered-empty
// line, the error block, a bounded list that scrolls itself and hands a wheel
// to the page at its ends, and attemptRequested for a row naming an attempt.
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

  function rowOf(pane, seq) { return H.find(pane, "eventsRow" + seq) }
  function part(pane, seq, name) { return H.find(rowOf(pane, seq), name) }
  function listOf(pane) { return H.find(pane, "eventsList") }

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
}
