import QtQuick

// The one fade the panel animates with: `level` swings 1 -> 0.3 -> 1 for as
// long as the owner keeps `running` true, and is put back to 1 the moment it
// stops, so whatever follows it is never left faded. The owner decides when
// it runs (on screen AND something to show), so an idle view animates nothing.
// StatusPips' in-progress pips and RunBadge's running ring both follow it;
// write no second animation, bind to `level`.
SequentialAnimation {
  id: pulse

  property real level: 1

  loops: Animation.Infinite
  NumberAnimation { target: pulse; property: "level"; from: 1; to: 0.3; duration: 800; easing.type: Easing.InOutSine }
  NumberAnimation { target: pulse; property: "level"; from: 0.3; to: 1; duration: 800; easing.type: Easing.InOutSine }
  onRunningChanged: if (!running) pulse.level = 1
}
