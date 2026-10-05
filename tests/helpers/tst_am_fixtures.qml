// tests/helpers/tst_am_fixtures.qml
// amFixtures.js: load(name) returns a fresh parse of tests/fixtures/am/<name>
// on every call and throws an Error whose message names <name> when the file
// cannot be read or parsed. Needs QML_XHR_ALLOW_FILE_READ=1 (tests/run.sh).
import QtQuick
import QtTest
import "amFixtures.js" as F

TestCase {
  id: tc
  name: "AmFixtures"

  readonly property var names: [
    "runs.json", "status-started.json", "status-done.json", "status-escalated.json",
    "status-escalated-integrate.json", "status-done-integrate.json", "watch-events.json",
    "watch-hello.json", "logs-attempt.json"
  ]

  function test_every_fixture_loads() {
    for (var i = 0; i < names.length; i++) {
      var f = F.load(names[i])
      verify(f !== null && typeof f === "object", names[i])
    }
  }

  function test_loads_real_content() {
    var runs = F.load("runs.json")
    compare(runs.ok, true)
    verify(Array.isArray(runs.data.runs), "runs.json data.runs is an array")
    compare(F.load("watch-hello.json").schema_2.schema, 2)
  }

  function test_underscore_keys_are_kept() {
    compare(typeof F.load("watch-hello.json")._note, "string")
  }

  function test_two_loads_are_distinct() {
    var a = F.load("status-done.json")
    var b = F.load("status-done.json")
    verify(a !== b, "same object returned twice")
    verify(a.data !== b.data, "same data object returned twice")
    compare(JSON.stringify(a), JSON.stringify(b))
    // A mutation on a fresh copy.
    a.data.run.status = "canceled"
    compare(b.data.run.status, "done")
    compare(F.load("status-done.json").data.run.status, "done")
  }

  function test_array_edits_do_not_leak_into_later_loads() {
    var n = F.load("runs.json").data.runs.length
    var a = F.load("runs.json")
    // A mutation on a fresh copy.
    a.data.runs.push({ id: "extra" })
    compare(F.load("runs.json").data.runs.length, n)
  }

  function test_a_test_in_another_dir_loads_through_the_documented_import() {
    var o = Qt.createQmlObject(
      'import QtQml\nimport "../helpers/amFixtures.js" as F\nQtObject { property var r: F.load("runs.json") }',
      tc, Qt.resolvedUrl("../core/AmFixturesProbe.qml"))
    verify(o.r !== null && typeof o.r === "object", "no object from tests/core")
    compare(o.r.ok, true)
    o.destroy()
  }
}
