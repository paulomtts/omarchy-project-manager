.pragma library

// Live log stream: folds the JSON lines runs-logs-follow.py prints (am's
// `am logs --follow` hello, chunk and end lines, or one {"ok":false,"error"}
// refusal) into a bounded buffer of display lines. Pure and never throwing;
// no function mutates its arguments.

var _CONTROLS_RE = /[\x00-\x08\x0b-\x1f\x7f]/g

function _inRange(c, lo, hi) { return c >= lo && c <= hi }

// Index where plain text resumes after the ESC at text[j - 1]. A CSI ends at
// its first character in U+0040-U+007E, an OSC at BEL or ESC \; either stops
// before a "\n" or at the end. Another ESC sequence is intermediates
// (U+0020-U+002F) then one final in U+0030-U+007E; anything else is the ESC
// alone.
function _escapeEnd(text, j) {
  var n = text.length
  if (j >= n) return n
  var c = text.charCodeAt(j)
  var k = j + 1
  if (c === 0x5b) {
    for (; k < n; k++) {
      var p = text.charCodeAt(k)
      if (p === 0x0a) return k
      if (_inRange(p, 0x40, 0x7e)) return k + 1
    }
    return n
  }
  if (c === 0x5d) {
    for (; k < n; k++) {
      var o = text.charCodeAt(k)
      if (o === 0x0a) return k
      if (o === 0x07) return k + 1
      if (o === 0x1b && k + 1 < n && text.charCodeAt(k + 1) === 0x5c) return k + 2
    }
    return n
  }
  k = j
  while (k < n && _inRange(text.charCodeAt(k), 0x20, 0x2f)) k++
  if (k < n && _inRange(text.charCodeAt(k), 0x30, 0x7e)) return k + 1
  return j
}

function _stripEscapes(text) {
  var out = ""
  var start = 0
  var i = text.indexOf("\x1b")
  while (i >= 0) {
    out += text.slice(start, i)
    start = _escapeEnd(text, i + 1)
    i = text.indexOf("\x1b", start)
  }
  return out + text.slice(start)
}

// The last non-empty "\r"-separated segment of line, or "".
function _lastFrame(line) {
  var frames = line.split("\r")
  for (var i = frames.length - 1; i >= 0; i--)
    if (frames[i] !== "") return frames[i]
  return ""
}

// text without ANSI CSI/OSC/ESC sequences, "\r\n" as "\n", each line reduced
// to its last "\r" frame, and without C0 controls other than "\t" and "\n"
// or DEL. "" for a non-string.
function sanitize(text) {
  if (typeof text !== "string") return ""
  var lines = _stripEscapes(text).replace(/\r\n/g, "\n").split("\n")
  for (var i = 0; i < lines.length; i++)
    if (lines[i].indexOf("\r") >= 0) lines[i] = _lastFrame(lines[i])
  return lines.join("\n").replace(_CONTROLS_RE, "")
}

// The UTF-8 byte length of text; a lone surrogate counts 3 (U+FFFD). 0 for a
// non-string.
function utf8Length(text) {
  if (typeof text !== "string") return 0
  var bytes = 0
  for (var i = 0; i < text.length; i++) {
    var c = text.charCodeAt(i)
    if (c < 0x80) bytes += 1
    else if (c < 0x800) bytes += 2
    else if (_inRange(c, 0xd800, 0xdbff) && i + 1 < text.length && _inRange(text.charCodeAt(i + 1), 0xdc00, 0xdfff)) {
      bytes += 4
      i++
    } else bytes += 3
  }
  return bytes
}
