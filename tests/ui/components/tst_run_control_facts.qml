// tests/ui/components/tst_run_control_facts.qml
// ui/components/runControlFacts.js: the store's per-run control facts read
// with own-key checks, so an id such as `constructor` or `__proto__` is just an
// id with nothing pending.
import QtQuick
import QtTest
import "../../../ui/components/runControlFacts.js" as Facts

TestCase {
  name: "RunControlFacts"

  function test_run_id_of() {
    compare(Facts.runIdOf({ id: "r1" }), "r1")
    compare(Facts.runIdOf({ id: 5 }), "")
    compare(Facts.runIdOf({}), "")
    compare(Facts.runIdOf(null), "")
    compare(Facts.runIdOf("r1"), "")
  }

  function test_pending_of() {
    var r = { id: "r1" }
    compare(Facts.pendingOf({ r1: "pause" }, r), "pause")
    compare(Facts.pendingOf({ r2: "pause" }, r), "")
    compare(Facts.pendingOf({ r1: 5 }, r), "", "only a string is an action")
    compare(Facts.pendingOf({ r1: "pause" }, null), "")
    compare(Facts.pendingOf(null, r), "")
    compare(Facts.pendingOf(undefined, r), "")
    compare(Facts.pendingOf({ "": "pause" }, { id: "" }), "", "no id, nothing pending")
  }

  // Review Focus 2.
  function test_inherited_names_are_not_pending_waiting_or_in_error() {
    var names = ["constructor", "__proto__", "toString", "hasOwnProperty"]
    for (var i = 0; i < names.length; i++) {
      var r = { id: names[i] }
      compare(Facts.pendingOf({}, r), "", names[i])
      compare(Facts.waitingOf({}, r), false, names[i])
    }
  }

  function test_waiting_of() {
    var r = { id: "r1" }
    compare(Facts.waitingOf({ r1: true }, r), true)
    compare(Facts.waitingOf({ r1: "yes" }, r), false, "only true is waiting")
    compare(Facts.waitingOf({ r2: true }, r), false)
    compare(Facts.waitingOf(null, r), false)
    compare(Facts.waitingOf({ r1: true }, null), false)
  }

  function test_error_of() {
    var r = { id: "r1" }
    compare(Facts.errorOf("The run is not running", "r1", r), "The run is not running")
    compare(Facts.errorOf("The run is not running", "r2", r), "", "another run's error")
    compare(Facts.errorOf("boom", "", { id: "" }), "", "no id matches no error")
    compare(Facts.errorOf("boom", "r1", null), "")
    compare(Facts.errorOf("", "r1", r), "")
    compare(Facts.errorOf(undefined, "r1", r), "")
  }
}
