.pragma library

// Live log stream: folds the JSON lines runs-logs-follow.py prints (am's
// `am logs --follow` hello, chunk and end lines, or one {"ok":false,"error"}
// refusal) into a bounded buffer of display lines.
//
// Buffer: { lines, partial, dropped, nextOffset, gapBytes, slack, maxLines }.
// lines: sanitized display lines, oldest first, at most maxLines. partial: the
// unterminated tail, unsanitized. dropped: lines removed from the front.
// nextOffset: the byte offset the next chunk is expected at. gapBytes: bytes
// skipped by gaps. slack: how far below nextOffset a chunk is still contiguous
// (2 per U+FFFD in the last chunk). Pure and never throwing; no function
// mutates its arguments.

var _DEFAULT_MAX_LINES = 1000
var _MAX_LINE = 2000
var _MAX_PARTIAL = 16384
var _ELLIPSIS = "\u2026"
var _CONTROLS_RE = /[\x00-\x08\x0b-\x1f\x7f]/g

function _isObject(v) { return v !== null && typeof v === "object" && !Array.isArray(v) }
function _has(o, key) { return Object.prototype.hasOwnProperty.call(o, key) }
function _inRange(c, lo, hi) { return c >= lo && c <= hi }
function _isByteOffset(v) { return typeof v === "number" && isFinite(v) && Math.floor(v) === v && v >= 0 }
function _isMaxLines(v) { return typeof v === "number" && isFinite(v) && Math.floor(v) === v && v >= 1 }
function _count(v) { return typeof v === "number" && isFinite(v) && v >= 0 ? v : 0 }

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

// A new empty buffer; maxLines is kept when a finite integer >= 1, else 1000.
function emptyBuffer(maxLines) {
  return { lines: [], partial: "", dropped: 0, nextOffset: 0, gapBytes: 0, slack: 0,
           maxLines: _isMaxLines(maxLines) ? maxLines : _DEFAULT_MAX_LINES }
}

// A new copy of buffer with every invalid field read as its emptyBuffer value;
// emptyBuffer(buffer.maxLines) when buffer has no array lines.
function _read(buffer) {
  if (!_isObject(buffer) || !Array.isArray(buffer.lines)) return emptyBuffer(buffer ? buffer.maxLines : undefined)
  return { lines: buffer.lines.slice(),
           partial: typeof buffer.partial === "string" ? buffer.partial : "",
           dropped: _count(buffer.dropped), nextOffset: _count(buffer.nextOffset),
           gapBytes: _count(buffer.gapBytes), slack: _count(buffer.slack),
           maxLines: _isMaxLines(buffer.maxLines) ? buffer.maxLines : _DEFAULT_MAX_LINES }
}

function _isEmpty(b) {
  return b.lines.length === 0 && b.partial === "" && b.dropped === 0 && b.nextOffset === 0 && b.gapBytes === 0
}

// sanitize(raw) cut to 2000 characters plus "…", never splitting a surrogate pair.
function _displayLine(raw) {
  var line = sanitize(raw)
  if (line.length <= _MAX_LINE) return line
  var end = _inRange(line.charCodeAt(_MAX_LINE - 1), 0xd800, 0xdbff) ? _MAX_LINE - 1 : _MAX_LINE
  return line.slice(0, end) + _ELLIPSIS
}

function _cap(b) {
  var extra = b.lines.length - b.maxLines
  if (extra <= 0) return
  b.lines.splice(0, extra)
  b.dropped += extra
}

// b (already a copy) with the chunk {offset, text} folded in.
function _foldChunk(b, offset, text) {
  if (offset < b.nextOffset - b.slack) return { buffer: b, kind: "ignored" }
  var raw = b.partial
  if (offset > b.nextOffset) {
    var gap = offset - b.nextOffset
    b.gapBytes += gap
    if (raw !== "") b.lines.push(_displayLine(raw))
    raw = ""
    b.lines.push("[" + _ELLIPSIS + " " + gap + " bytes not shown]")
  }
  raw += text
  var last = raw.lastIndexOf("\n")
  if (last >= 0) {
    var done = raw.slice(0, last).split("\n")
    for (var i = 0; i < done.length; i++) b.lines.push(_displayLine(done[i]))
    raw = raw.slice(last + 1)
  }
  if (raw.length > _MAX_PARTIAL) {
    b.lines.push(_displayLine(raw))
    raw = ""
  }
  b.partial = raw
  b.nextOffset = offset + utf8Length(text)
  b.slack = 2 * (text.split("\uFFFD").length - 1)
  _cap(b)
  return { buffer: b, kind: "chunk" }
}

// {buffer, kind}: line folded into a new copy of buffer. kind is "refusal"
// (own ok === false), "hello" (event "logs"), "end" (event "end"), "chunk"
// ({offset, text} at or after nextOffset - slack) or "ignored". A hello sets
// nextOffset to its offset on an empty buffer only; a chunk past nextOffset
// first appends "[… N bytes not shown]". Only hello and chunk change the buffer.
function foldLine(buffer, line) {
  var b = _read(buffer)
  if (!_isObject(line)) return { buffer: b, kind: "ignored" }
  if (_has(line, "ok") && line.ok === false) return { buffer: b, kind: "refusal" }
  if (line.event === "logs") {
    if (_isEmpty(b) && _isByteOffset(line.offset)) b.nextOffset = line.offset
    return { buffer: b, kind: "hello" }
  }
  if (line.event === "end") return { buffer: b, kind: "end" }
  if (_has(line, "event") || _has(line, "ok")) return { buffer: b, kind: "ignored" }
  if (!_isByteOffset(line.offset) || typeof line.text !== "string") return { buffer: b, kind: "ignored" }
  return _foldChunk(b, line.offset, line.text)
}

// The display text: "… N earlier lines" when dropped > 0, the lines, then the
// sanitized and cut partial when not "", joined by "\n". "" for a bad buffer.
function bufferText(buffer) {
  if (!_isObject(buffer) || !Array.isArray(buffer.lines)) return ""
  var dropped = _count(buffer.dropped)
  var out = dropped > 0 ? [_ELLIPSIS + " " + dropped + " earlier lines"] : []
  out = out.concat(buffer.lines)
  var tail = _displayLine(typeof buffer.partial === "string" ? buffer.partial : "")
  if (tail !== "") out.push(tail)
  return out.join("\n")
}
