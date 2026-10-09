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
}
