.pragma library

// The one glyph per am run state, shared by RunBadge and RunRollupBar so a
// state reads the same everywhere. Plain BMP characters, never a Nerd Font
// code point. State is never shown by colour alone: every state has its glyph.
var GLYPHS = {
  running: "⟳",
  parked: "⏸",
  escalated: "‼",
  dead: "✖",
  cancelled: "⊘",
  done: "✔"
}

// The order a parent's counts are read in.
var COUNT_ORDER = ["running", "parked", "escalated", "done"]

// The glyph for a run state; "" for anything else ("", "none", "bogus", and
// inherited names such as "constructor").
function glyphOf(state) {
  return typeof state === "string" && Object.prototype.hasOwnProperty.call(GLYPHS, state) ? GLYPHS[state] : ""
}

// One count of a rollup-shaped object. A missing field, a non-object, a
// negative or anything but a finite number (a numeric string, a boolean,
// Infinity) is 0.
function countOf(counts, key) {
  if (counts === null || typeof counts !== "object") return 0
  var n = counts[key]
  return typeof n === "number" && isFinite(n) && n > 0 ? n : 0
}

// A parent's non-zero counts as "glyph N" pairs, e.g. "⟳ 2 ⏸ 1"; "" when none.
function countsText(counts) {
  var parts = []
  for (var i = 0; i < COUNT_ORDER.length; i++) {
    var n = countOf(counts, COUNT_ORDER[i])
    if (n > 0) parts.push(GLYPHS[COUNT_ORDER[i]] + " " + n)
  }
  return parts.join(" ")
}
