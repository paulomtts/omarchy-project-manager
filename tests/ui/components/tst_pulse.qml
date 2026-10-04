// tests/ui/components/tst_pulse.qml
// ui/components/Pulse.qml: the one fade the panel animates with. `level` rests
// at 1, swings between 0.3 and 1 while running, and is put back to 1 the
// moment it stops, so nothing driven by it is ever left faded.
import QtQuick
import QtTest
import "../../../ui/components" as UI

TestCase {
  id: tc
  name: "Pulse"
  when: windowShown
  visible: true
  width: 200; height: 100

  Component { id: pulseC; UI.Pulse {} }

  function test_level_rests_at_one_until_the_owner_starts_it() {
    var pulse = createTemporaryObject(pulseC, tc)
    compare(pulse.running, false, "nothing runs unless the owner says so")
    compare(pulse.level, 1)
    compare(pulse.loops, -1, "loops forever (Animation.Infinite reads -1; the enum constant does not compare equal in qmltestrunner)")
  }

  function test_level_fades_while_running_and_is_put_back_when_it_stops() {
    var pulse = createTemporaryObject(pulseC, tc)
    pulse.running = true
    wait(120)
    verify(pulse.level < 1, "it fades")
    verify(pulse.level >= 0.3, "never below 0.3")
    pulse.running = false
    wait(30)
    compare(pulse.level, 1, "a stopped pulse leaves nothing faded")
  }
}
