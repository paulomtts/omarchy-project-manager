// tests/core/domain/tst_run_events.qml
import QtQuick
import QtTest
import "../../../core/domain/runEvents.js" as RE
import "../../../core/domain/runs.js" as Runs
import "../../helpers/amFixtures.js" as F

// eventRow's input comes from tests/fixtures/am/events.json (am 0.2.0, run
// 20261008T143807Z-63060df3) via events().
TestCase {
  name: "DomainRunEvents"

  readonly property string keys: "attempt,card,detail,duration,glyph,label,level,phase,seq,status,time"
  readonly property string storyId: "ae1e3ba6-cc07-4e9d-aff7-db161c3be234"
  readonly property string cardId: "7442d674-e0d4-4048-96ee-cd27b5ba34f8"

  // The fixture's journal events, a fresh copy on every call.
  function events() { return F.load("events.json").data.events }

  // Titles for the fixture's story and its first subtask.
  function titles() {
    var t = {}
    t[storyId] = "Control domain"
    t[cardId] = "runs.js control"
    return t
  }

  // Every non-null eventRow of events(): 59 rows, seq 2..60 in order.
  function fixtureRows() {
    var all = events()
    var out = []
    for (var i = 0; i < all.length; i++) {
      var r = RE.eventRow(all[i], titles(), 0)
      if (r !== null) out.push(r)
    }
    return out
  }

  // A deep copy of a row.
  function copyRow(row) { return JSON.parse(JSON.stringify(row)) }

  // The rows' seqs joined with ",".
  function seqList(rows) {
    var s = []
    for (var i = 0; i < rows.length; i++) s.push(rows[i].seq)
    return s.join(",")
  }

  // The integers a..b joined with ",".
  function seqRange(a, b) {
    var s = []
    for (var i = a; i <= b; i++) s.push(i)
    return s.join(",")
  }

  function test_duration_text() {
    var blanks = [null, undefined, "4.2", NaN, Infinity, -Infinity, -1]
    for (var i = 0; i < blanks.length; i++) compare(RE.durationText(blanks[i]), "", String(blanks[i]))
    compare(RE.durationText(0.031444113003090024), "0.0s")
    compare(RE.durationText(0), "0.0s")
    compare(RE.durationText(4.21), "4.2s")
    compare(RE.durationText(59.94), "59.9s")
    compare(RE.durationText(59.96), "1m 00s")
    compare(RE.durationText(60), "1m 00s")
    compare(RE.durationText(192.4), "3m 12s")
    compare(RE.durationText(422), "7m 02s")
    compare(RE.durationText(4500), "75m 00s")
  }

  function test_run_started_from_fixture() {
    var r = RE.eventRow(events()[1], {}, 0)
    compare(Object.keys(r).sort().join(","), keys)
    compare(r.seq, 2)
    compare(r.time, "14:38:07")
    compare(r.level, "run")
    compare(r.label, "run started")
    compare(r.status, "started")
    compare(r.glyph, "running")
    compare(r.duration, "")
    compare(r.detail, "")
    compare(r.card, "")
    compare(r.phase, "")
    compare(r.attempt, 0)
  }

  function test_run_labels() {
    var cases = [["done", "run done", "done"], ["stopped", "run paused", "parked"],
                 ["escalated", "run escalated", "escalated"], ["cancelled", "run cancelled", "cancelled"],
                 ["canceled", "run cancelled", "cancelled"], ["weird", "run weird", ""]]
    for (var i = 0; i < cases.length; i++) {
      // synthetic: the fixture's run_upsert with its status edited
      var e = events()[1]
      e.payload.status = cases[i][0]
      var r = RE.eventRow(e, {}, 0)
      compare(r.label, cases[i][1], cases[i][0])
      compare(r.glyph, cases[i][2], cases[i][0])
      compare(r.status, cases[i][0], cases[i][0])
    }
    // synthetic: the fixture's run_upsert without a status
    var bare = events()[1]
    delete bare.payload.status
    var b = RE.eventRow(bare, {}, 0)
    compare(b.label, "run")
    compare(b.status, "")
    compare(b.glyph, "")
    // synthetic: a status that is not a string
    var odd = [5, null, { s: "done" }]
    for (var j = 0; j < odd.length; j++) {
      var o = events()[1]
      o.payload.status = odd[j]
      var r2 = RE.eventRow(o, {}, 0)
      compare(r2.label, "run", String(odd[j]))
      compare(r2.status, "", String(odd[j]))
      compare(r2.glyph, "", String(odd[j]))
    }
  }

  function test_story_row() {
    var r = RE.eventRow(events()[2], titles(), 0)
    compare(r.level, "story")
    compare(r.label, "Control domain")
    compare(r.status, "pending")
    compare(r.glyph, "")
    compare(r.card, "")
    compare(r.seq, 3)
    compare(RE.eventRow(events()[2], {}, 0).label, "…1c3be234")
  }

  function test_subtask_row() {
    var r = RE.eventRow(events()[3], titles(), 0)
    compare(r.level, "subtask")
    compare(r.label, "runs.js control")
    compare(r.card, cardId)
    compare(r.status, "pending")
    compare(r.glyph, "")
    var bare = RE.eventRow(events()[3], {}, 0)
    compare(bare.label, Runs.shortId({ id: cardId }))
    compare(bare.label, "…b5ba34f8")
    // synthetic: the fixture's subtask_upsert with its status edited
    var e = events()[3]
    e.payload.status = "escalated"
    compare(RE.eventRow(e, titles(), 0).glyph, "escalated")
    e.payload.status = "stopped"
    compare(RE.eventRow(e, titles(), 0).glyph, "parked")
  }

  function test_phase_rows() {
    var started = RE.eventRow(events()[18], titles(), 0)
    var done = RE.eventRow(events()[19], titles(), 0)
    compare(started.level, "phase")
    compare(started.label, "runs.js control worktree")
    compare(done.label, "runs.js control worktree")
    compare(started.status, "started")
    compare(done.status, "done")
    compare(started.glyph, "running")
    compare(done.glyph, "done")
    compare(started.phase, "worktree")
    compare(started.attempt, 0)
    compare(started.detail, "")
    compare(started.duration, "")
    compare(started.card, cardId)
  }

  function test_failed_phase_detail() {
    // synthetic: the fixture's done worktree phase edited to failed with a detail
    var e = events()[19]
    e.payload.status = "failed"
    e.payload.detail = "3 tests red"
    var r = RE.eventRow(e, titles(), 0)
    compare(r.glyph, "dead")
    compare(r.detail, "3 tests red")
    e.payload.detail = null
    compare(RE.eventRow(e, titles(), 0).detail, "")
  }

  function test_attempt_rows() {
    var started = RE.eventRow(events()[21], titles(), 0)
    compare(started.level, "attempt")
    compare(started.label, "runs.js control explore.1")
    compare(started.attempt, 1)
    compare(started.phase, "explore")
    compare(started.glyph, "running")
    compare(started.duration, "")
    var ok = RE.eventRow(events()[22], titles(), 0)
    compare(ok.status, "ok")
    compare(ok.glyph, "done")
    compare(ok.duration, "0.0s")
  }

  function test_attempt_failures() {
    var failures = ["gate_failed", "schema_invalid", "harness_error"]
    for (var i = 0; i < failures.length; i++) {
      // synthetic: the fixture's ok attempt with its status edited
      var e = events()[22]
      e.payload.status = failures[i]
      compare(RE.eventRow(e, titles(), 0).glyph, "dead", failures[i])
    }
    // synthetic: a longer attempt
    var long = events()[22]
    long.payload.duration = 192.4
    compare(RE.eventRow(long, titles(), 0).duration, "3m 12s")
  }

  function test_attempt_number_fallback() {
    // synthetic: the attempt number only in the payload
    var e = events()[21]
    e.attempt = null
    e.payload.n = 2
    var r = RE.eventRow(e, titles(), 0)
    compare(r.attempt, 2)
    compare(r.label, "runs.js control explore.2")
    // synthetic: no attempt number at all
    delete e.payload.n
    var none = RE.eventRow(e, titles(), 0)
    compare(none.attempt, 0)
    compare(none.label, "runs.js control explore")
    // synthetic: an attempt number on a phase event is not an attempt
    var p = events()[18]
    p.attempt = 3
    var phase = RE.eventRow(p, titles(), 0)
    compare(phase.attempt, 0)
    compare(phase.label, "runs.js control worktree")
  }

  function test_phase_name_fallback() {
    // synthetic: the phase name only in the payload
    var e = events()[18]
    e.phase = null
    e.payload.name = "verify"
    var r = RE.eventRow(e, titles(), 0)
    compare(r.phase, "verify")
    compare(r.label, "runs.js control verify")
    // synthetic: no phase name at all
    delete e.payload.name
    var none = RE.eventRow(e, titles(), 0)
    compare(none.phase, "")
    compare(none.label, "runs.js control")
  }

  function test_time_offsets() {
    var cases = [[0, "14:38:07"], [120, "16:38:07"], [-330, "09:08:07"], [600, "00:38:07"],
                 [-900, "23:38:07"], [90.4, "16:08:07"], [89.6, "16:08:07"], [-0.4, "14:38:07"],
                 [NaN, "14:38:07"], [undefined, "14:38:07"], ["120", "14:38:07"], [Infinity, "14:38:07"]]
    for (var i = 0; i < cases.length; i++)
      compare(RE.eventRow(events()[1], {}, cases[i][0]).time, cases[i][1], String(cases[i][0]))
    compare(RE.eventRow(events()[1], {}).time, "14:38:07")
    verify(/^\d\d:\d\d:\d\d$/.test(RE.eventRow(events()[1], {}, 1e9).time))
    // synthetic: a ts one microsecond short of the next second
    var e = events()[1]
    e.ts = "2026-10-08T00:00:59.999999Z"
    compare(RE.eventRow(e, {}, 0).time, "00:00:59")
    // synthetic: a ts with no fraction
    e.ts = "2026-10-08T14:38:07Z"
    compare(RE.eventRow(e, {}, 0).time, "14:38:07")
  }

  function test_bad_ts() {
    var bad = [5, "yesterday", "2026-10-08T14:38:07", "2026-10-08T14:38:07+00:00", "2026-10-08T14:38:07z", null]
    for (var i = 0; i < bad.length; i++) {
      // synthetic: the fixture's run_upsert with its ts edited
      var e = events()[1]
      e.ts = bad[i]
      var r = RE.eventRow(e, {}, 0)
      compare(r.time, "", String(bad[i]))
      compare(r.label, "run started", String(bad[i]))
      compare(r.seq, 2, String(bad[i]))
    }
    // synthetic: no ts
    var none = events()[1]
    delete none.ts
    compare(RE.eventRow(none, {}, 0).time, "")
  }

  function test_duration_only_on_attempts() {
    // synthetic: a duration on a phase event
    var p = events()[18]
    p.payload.duration = 5
    compare(RE.eventRow(p, titles(), 0).duration, "")
    // synthetic: a detail on a subtask and on an attempt event
    var s = events()[3]
    s.payload.detail = "why"
    compare(RE.eventRow(s, titles(), 0).detail, "")
    var a = events()[22]
    a.payload.detail = "why"
    compare(RE.eventRow(a, titles(), 0).detail, "")
  }

  function test_unknown_events_ignored() {
    compare(RE.eventRow(events()[0], {}, 0), null)
    var names = ["control_requested", "control_handled", "claim_conflict", "lease_released", "bogus",
                 "constructor", "toString", "__proto__", "", 5, null]
    for (var i = 0; i < names.length; i++) {
      // synthetic: the fixture's run_upsert renamed
      var e = events()[1]
      e.event = names[i]
      compare(RE.eventRow(e, {}, 0), null, String(names[i]))
    }
    // synthetic: no event name
    var none = events()[1]
    delete none.event
    compare(RE.eventRow(none, {}, 0), null)
  }

  function test_bad_inputs() {
    var notEvents = [null, undefined, "x", 5, [], [events()[1]]]
    for (var i = 0; i < notEvents.length; i++) compare(RE.eventRow(notEvents[i], {}, 0), null, String(notEvents[i]))
    compare(RE.eventRow(), null)

    var payloads = [null, "x", 5, []]
    for (var j = 0; j < payloads.length; j++) {
      // synthetic: the fixture's ok attempt with its payload replaced
      var e = events()[22]
      e.payload = payloads[j]
      var r = RE.eventRow(e, titles(), 0)
      compare(Object.keys(r).sort().join(","), keys, String(payloads[j]))
      compare(r.status, "", String(payloads[j]))
      compare(r.glyph, "", String(payloads[j]))
      compare(r.duration, "", String(payloads[j]))
      compare(r.label, "runs.js control explore.1", String(payloads[j]))
    }
    // synthetic: no payload
    var bare = events()[22]
    delete bare.payload
    compare(RE.eventRow(bare, titles(), 0).status, "")

    var short = Runs.shortId({ id: cardId })
    var badTitles = [null, undefined, [], "x", 5]
    for (var k = 0; k < badTitles.length; k++)
      compare(RE.eventRow(events()[3], badTitles[k], 0).label, short, String(badTitles[k]))
    var t = {}
    t[cardId] = ""
    compare(RE.eventRow(events()[3], t, 0).label, short)
    t[cardId] = 7
    compare(RE.eventRow(events()[3], t, 0).label, short)
    t[cardId] = null
    compare(RE.eventRow(events()[3], t, 0).label, short)

    // synthetic: card ids that name inherited properties
    var ctor = events()[3]
    ctor.card = "constructor"
    compare(RE.eventRow(ctor, {}, 0).label, "…structor")
    compare(RE.eventRow(ctor, { constructor: "Ctor" }, 0).label, "Ctor")
    var proto = events()[3]
    proto.card = "__proto__"
    compare(RE.eventRow(proto, {}, 0).label, "…_proto__")
    // synthetic: a story id that is not a string
    var numeric = events()[2]
    numeric.story = 5
    compare(RE.eventRow(numeric, titles(), 0).label, "…")

    // synthetic: seq missing or not a number
    var noSeq = events()[1]
    delete noSeq.seq
    compare(RE.eventRow(noSeq, {}, 0).seq, 0)
    noSeq.seq = "2"
    compare(RE.eventRow(noSeq, {}, 0).seq, 0)
    noSeq.seq = NaN
    compare(RE.eventRow(noSeq, {}, 0).seq, 0)
  }

  function test_unknown_keys_and_no_cost() {
    // synthetic: the fixture's ok attempt with keys am no longer writes
    var e = events()[22]
    e.payload.cost = 0.12
    e.payload.tokens = 3400
    e.payload.extra = { any: "thing" }
    var r = RE.eventRow(e, titles(), 0)
    compare(Object.keys(r).sort().join(","), keys)
    compare(r.hasOwnProperty("cost"), false)
    compare(r.hasOwnProperty("tokens"), false)
  }

  function test_does_not_mutate() {
    var all = events()
    var t = titles()
    for (var i = 0; i < all.length; i++) {
      var before = JSON.stringify(all[i])
      var titlesBefore = JSON.stringify(t)
      RE.eventRow(all[i], t, 120)
      compare(JSON.stringify(all[i]), before, "event " + i)
      compare(JSON.stringify(t), titlesBefore, "titles after event " + i)
    }
  }

  function test_glyph_is_runs_mapping() {
    var allowed = ["running", "parked", "escalated", "dead", "cancelled", "done", ""]
    var statuses = ["started", "done", "escalated", "stopped", "cancelled", "canceled", "pending", "failed",
                    "ok", "schema_invalid", "gate_failed", "harness_error"]
    for (var i = 0; i < statuses.length; i++) {
      // synthetic: the fixture's ok attempt with its status edited
      var e = events()[22]
      e.payload.status = statuses[i]
      var glyph = RE.eventRow(e, titles(), 0).glyph
      compare(glyph, Runs.glyphStateOf(statuses[i]), statuses[i])
      verify(allowed.indexOf(glyph) !== -1, statuses[i])
    }
  }

  function test_fold_append() {
    var all = fixtureRows()
    compare(all.length, 59)
    var r = RE.foldEvents(all.slice(0, 30), all.slice(30), 500)
    compare(r.rows.length, 59)
    compare(seqList(r.rows), seqRange(2, 60))
    compare(r.dropped, 0)
    verify(r.rows[0] === all[0])
    verify(r.rows[58] === all[58])
    compare(seqList(RE.foldEvents([], fixtureRows(), 500).rows), seqRange(2, 60))
  }

  function test_fold_prepend() {
    var all = fixtureRows()
    var r = RE.foldEvents(all.slice(30), all.slice(0, 30), 500)
    compare(seqList(r.rows), seqRange(2, 60))
    compare(r.dropped, 0)
  }

  function test_fold_out_of_order() {
    var reversed = fixtureRows().reverse()
    compare(seqList(RE.foldEvents([], reversed, 500).rows), seqRange(2, 60))
    var all = fixtureRows()
    var shuffled = []
    for (var i = 0; i < all.length; i++) shuffled.push(all[(i * 7) % all.length])
    compare(seqList(RE.foldEvents([], shuffled, 500).rows), seqRange(2, 60))
    compare(seqList(RE.foldEvents(fixtureRows().reverse(), [], 500).rows), seqRange(2, 60))
    compare(seqList(RE.foldEvents(shuffled.slice(0, 30), shuffled.slice(30), 500).rows), seqRange(2, 60))
  }

  function test_fold_dedupe() {
    var all = fixtureRows()
    var r = RE.foldEvents(all.slice(0, 39), all.slice(28), 500)
    compare(all[38].seq, 40)
    compare(all[28].seq, 30)
    compare(r.rows.length, 59)
    compare(seqList(r.rows), seqRange(2, 60))
    compare(r.dropped, 0)
    var twice = RE.foldEvents(fixtureRows(), fixtureRows(), 500)
    compare(twice.rows.length, 59)
    compare(seqList(twice.rows), seqRange(2, 60))
    compare(twice.dropped, 0)
  }

  function test_fold_incoming_wins() {
    var base = fixtureRows()[8]
    compare(base.seq, 10)
    // synthetic: a held row and an incoming row with the same seq
    var held = copyRow(base)
    held.label = "old"
    var incoming = copyRow(base)
    incoming.label = "new"
    var r = RE.foldEvents([held], [incoming], 500)
    compare(r.rows.length, 1)
    verify(r.rows[0] === incoming)
    compare(r.rows[0].label, "new")
    compare(r.dropped, 0)
    // synthetic: two incoming rows with the same seq
    var first = copyRow(base)
    first.label = "first"
    var second = copyRow(base)
    second.label = "second"
    var e = RE.foldEvents([], [first, second], 500)
    compare(e.rows.length, 1)
    verify(e.rows[0] === second)
    // synthetic: two held rows with the same seq and no incoming row
    var h = RE.foldEvents([first, second], [], 500)
    compare(h.rows.length, 1)
    verify(h.rows[0] === second)
    // synthetic: two rows with seq 0 (eventRow's seq for an event without one)
    var zeroA = copyRow(base)
    zeroA.seq = 0
    var zeroB = copyRow(base)
    zeroB.seq = 0
    var z = RE.foldEvents(fixtureRows(), [zeroA, zeroB], 500)
    compare(z.rows.length, 60)
    verify(z.rows[0] === zeroB)
    compare(seqList(z.rows), "0," + seqRange(2, 60))
  }

  function test_fold_cap() {
    var all = fixtureRows()
    var ten = RE.foldEvents([], all, 10)
    compare(seqList(ten.rows), seqRange(51, 60))
    compare(ten.dropped, 49)
    var exact = RE.foldEvents(all.slice(0, 30), all.slice(30), 59)
    compare(exact.rows.length, 59)
    compare(exact.dropped, 0)
    var one = RE.foldEvents(all.slice(0, 30), all.slice(30), 58)
    compare(seqList(one.rows), seqRange(3, 60))
    compare(one.dropped, 1)
    var dup = RE.foldEvents(fixtureRows(), fixtureRows(), 50)
    compare(dup.rows.length, 50)
    compare(seqList(dup.rows), seqRange(11, 60))
    compare(dup.dropped, 9)
    var heldOnly = RE.foldEvents(fixtureRows(), [], 10)
    compare(seqList(heldOnly.rows), seqRange(51, 60))
    compare(heldOnly.dropped, 49)
  }

  function test_fold_cap_default_and_bad() {
    // synthetic: 501 copies of one fixture row with seq 1..501
    var proto = fixtureRows()[0]
    var big = []
    for (var i = 1; i <= 501; i++) {
      var row = copyRow(proto)
      row.seq = i
      big.push(row)
    }
    var caps = [undefined, null, "10", NaN, Infinity, -1]
    for (var c = 0; c < caps.length; c++) {
      var r = RE.foldEvents([], big, caps[c])
      compare(r.rows.length, 500, String(caps[c]))
      compare(r.dropped, 1, String(caps[c]))
      compare(seqList(r.rows), seqRange(2, 501), String(caps[c]))
    }
    var omitted = RE.foldEvents([], big)
    compare(omitted.rows.length, 500)
    compare(omitted.dropped, 1)
    compare(omitted.rows[0].seq, 2)
    compare(omitted.rows[499].seq, 501)
    var frac = RE.foldEvents([], fixtureRows(), 2.9)
    compare(seqList(frac.rows), "59,60")
    compare(frac.dropped, 57)
    var zero = RE.foldEvents([], fixtureRows(), 0)
    verify(Array.isArray(zero.rows))
    compare(zero.rows.length, 0)
    compare(zero.dropped, 59)
  }

  function test_fold_bad_inputs() {
    var empties = [RE.foldEvents(), RE.foldEvents(null, null), RE.foldEvents("x", 5), RE.foldEvents({}, {})]
    for (var i = 0; i < empties.length; i++) {
      compare(Object.keys(empties[i]).sort().join(","), "dropped,rows", "case " + i)
      verify(Array.isArray(empties[i].rows), "case " + i)
      compare(empties[i].rows.length, 0, "case " + i)
      compare(empties[i].dropped, 0, "case " + i)
    }
    var row = fixtureRows()[0]
    // synthetic: entries that are not rows
    var junk = [null, undefined, 5, "x", [], {}, { seq: "3" }, { seq: NaN }, { seq: Infinity }]
    var inEvents = RE.foldEvents([], junk.concat([row]), 500)
    compare(inEvents.rows.length, 1)
    verify(inEvents.rows[0] === row)
    compare(inEvents.dropped, 0)
    var inRows = RE.foldEvents(junk.concat([row]), [], 500)
    compare(inRows.rows.length, 1)
    verify(inRows.rows[0] === row)
    compare(inRows.dropped, 0)
    var capped = RE.foldEvents(junk, junk.concat([row]), 1)
    compare(capped.rows.length, 1)
    verify(capped.rows[0] === row)
    compare(capped.dropped, 0)
    var all = events()
    var mapped = []
    for (var j = 0; j < all.length; j++) mapped.push(RE.eventRow(all[j], titles(), 0))
    compare(mapped[0], null)
    var folded = RE.foldEvents([], mapped, 500)
    compare(folded.rows.length, 59)
    compare(seqList(folded.rows), seqRange(2, 60))
    compare(folded.dropped, 0)
  }

  function test_fold_does_not_mutate() {
    var all = fixtureRows()
    var rows = all.slice(20).reverse()
    var evs = all.slice(0, 40)
    var rowsBefore = JSON.stringify(rows)
    var evsBefore = JSON.stringify(evs)
    var r = RE.foldEvents(rows, evs, 10)
    compare(JSON.stringify(rows), rowsBefore)
    compare(JSON.stringify(evs), evsBefore)
    verify(r.rows !== rows)
    verify(r.rows !== evs)
    var rowsLength = rows.length
    var evsLength = evs.length
    r.rows.push({ seq: 999 })
    r.rows.sort(function (a, b) { return b.seq - a.seq })
    compare(rows.length, rowsLength)
    compare(evs.length, evsLength)
    compare(JSON.stringify(rows), rowsBefore)
    compare(JSON.stringify(evs), evsBefore)
  }

  // synthetic: a copy of fixtureRows()[index] with its status edited.
  function withStatus(index, status) {
    var r = copyRow(fixtureRows()[index])
    r.status = status
    return r
  }

  function test_filter_all() {
    var rows = fixtureRows()
    var out = RE.filterRows(rows, "All")
    compare(out.length, 59)
    verify(out !== rows)
    for (var i = 0; i < rows.length; i++) verify(out[i] === rows[i], "row " + i)
  }

  function test_filter_phases() {
    var rows = fixtureRows()
    var out = RE.filterRows(rows, "Phases")
    compare(out.length, 42)
    var expected = []
    for (var i = 0; i < rows.length; i++)
      if (rows[i].level === "phase" || rows[i].level === "attempt") expected.push(rows[i])
    compare(expected.length, 42)
    for (var j = 0; j < out.length; j++) {
      verify(out[j] === expected[j], "row " + j)
      verify(out[j].level === "phase" || out[j].level === "attempt", "row " + j)
    }
  }

  function test_filter_failures() {
    // synthetic: fixture rows with failure statuses, interleaved with non-failures
    var failed = withStatus(17, "failed")
    var runEsc = withStatus(0, "escalated")
    var storyEsc = withStatus(1, "escalated")
    var subtaskEsc = withStatus(2, "escalated")
    var gate = withStatus(21, "gate_failed")
    var schema = withStatus(21, "schema_invalid")
    var harness = withStatus(21, "harness_error")
    var rows = [withStatus(0, "stopped"), failed, withStatus(2, "cancelled"), runEsc,
                withStatus(2, "canceled"), storyEsc, withStatus(1, "pending"), subtaskEsc,
                withStatus(21, "ok"), gate, withStatus(0, "done"), schema,
                withStatus(17, "started"), harness]
    var expected = [failed, runEsc, storyEsc, subtaskEsc, gate, schema, harness]
    var levels = ["phase", "run", "story", "subtask", "attempt", "attempt", "attempt"]
    for (var k = 0; k < expected.length; k++) compare(expected[k].level, levels[k], "level " + k)
    var out = RE.filterRows(rows, "Failures")
    compare(out.length, 7)
    for (var i = 0; i < expected.length; i++) verify(out[i] === expected[i], "row " + i)
    compare(RE.filterRows(fixtureRows(), "Failures").length, 0)
  }

  function test_filter_unknown() {
    var rows = fixtureRows()
    var filters = [undefined, null, "", "phases", "FAILURES", "bogus", 5]
    for (var f = 0; f < filters.length; f++) {
      var out = RE.filterRows(rows, filters[f])
      compare(out.length, 59, String(filters[f]))
      for (var i = 0; i < rows.length; i++) verify(out[i] === rows[i], String(filters[f]) + " row " + i)
    }
    compare(RE.filterRows(rows).length, 59)
  }

  function test_filter_bad_inputs() {
    var notRows = [[null, "All"], [undefined, undefined], ["x", "Phases"], [5, "Failures"], [{}, "All"]]
    for (var i = 0; i < notRows.length; i++) {
      var out = RE.filterRows(notRows[i][0], notRows[i][1])
      verify(Array.isArray(out), "case " + i)
      compare(out.length, 0, "case " + i)
    }
    compare(RE.filterRows().length, 0)
    var phase = fixtureRows()[17]
    compare(phase.level, "phase")
    // synthetic: entries that are not rows
    var mixed = [null, 5, "x", [], phase]
    var all = RE.filterRows(mixed, "All")
    compare(all.length, 1)
    verify(all[0] === phase)
    var phases = RE.filterRows(mixed, "Phases")
    compare(phases.length, 1)
    verify(phases[0] === phase)
    compare(RE.filterRows(mixed, "Failures").length, 0)
    // synthetic: statuses naming inherited properties, and a non-string status
    var odd = ["constructor", "toString", "__proto__", "hasOwnProperty", ["failed"], null, 5]
    for (var j = 0; j < odd.length; j++)
      compare(RE.filterRows([withStatus(21, odd[j])], "Failures").length, 0, String(odd[j]))
  }

  function test_filter_does_not_mutate() {
    var rows = fixtureRows()
    // synthetic: one failure row among the fixture rows
    rows[21] = withStatus(21, "gate_failed")
    var before = JSON.stringify(rows)
    var filters = ["All", "Phases", "Failures"]
    for (var f = 0; f < filters.length; f++) {
      var out = RE.filterRows(rows, filters[f])
      compare(JSON.stringify(rows), before, filters[f])
      verify(out !== rows, filters[f])
      out.push({ seq: 999 })
      compare(rows.length, 59, filters[f])
      compare(JSON.stringify(rows), before, filters[f])
    }
  }
}
