.pragma library
.import "runs.js" as Runs

// Run events timeline: one row per am journal event (`am events`).
// Pure and never throwing; reads no clock and no time zone.

function _isFiniteNumber(v) { return typeof v === "number" && isFinite(v) }
function _pad2(n) { return (n < 10 ? "0" : "") + n }

// An attempt's duration in seconds as text: below 60 (after rounding to one
// decimal) "S.Ss", else "Mm SSs" of the whole seconds. "" when seconds is not a
// finite number or is negative.
function durationText(seconds) {
  if (!_isFiniteNumber(seconds) || seconds < 0) return ""
  var tenths = Math.round(seconds * 10)
  if (tenths < 600) return (tenths / 10).toFixed(1) + "s"
  var whole = Math.round(seconds)
  return Math.floor(whole / 60) + "m " + _pad2(whole % 60) + "s"
}
