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

  function test_unknown_name_throws_naming_it() {
    try {
      F.load("no-such-fixture.json")
      fail("no throw for no-such-fixture.json")
    } catch (e) {
      verify(e instanceof Error, "not an Error: " + e)
      verify(e.message.indexOf("no-such-fixture.json") >= 0, e.message)
      verify(e.message.indexOf("not readable") >= 0, "a failed read reported as a parse failure: " + e.message)
    }
  }

  function test_directory_name_throws_naming_it() {
    try {
      F.load("")
      fail("no throw for the fixtures directory")
    } catch (e) {
      verify(e instanceof Error, "not an Error: " + e)
      verify(e.message.indexOf("amFixtures") >= 0, e.message)
    }
  }

  function test_a_name_without_extension_is_not_completed() {
    try {
      F.load("runs")
      fail("no throw for runs")
    } catch (e) {
      verify(e instanceof Error, "not an Error: " + e)
      verify(e.message.indexOf("runs") >= 0, e.message)
      verify(e.message.indexOf("amFixtures") >= 0, e.message)
    }
  }

  function test_malformed_json_throws_naming_it_and_the_cause() {
    var name = "../../helpers/testdata/bad.json"
    try {
      F.load(name)
      fail("no throw for " + name)
    } catch (e) {
      verify(e instanceof Error, "not an Error: " + e)
      verify(e.message.indexOf(name) >= 0, e.message)
      verify(e.message.indexOf("not readable") < 0, "a parse failure reported as a read failure: " + e.message)
    }
  }
}
