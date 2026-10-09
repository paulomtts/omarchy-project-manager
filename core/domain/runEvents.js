.pragma library
.import "runs.js" as Runs

// Run events timeline: one row per am journal event (`am events`).
//
// Input event, as am writes it:
//   { seq, gseq, ts, run_id, event, story, card, phase, attempt, payload }
// ts is UTC, "YYYY-MM-DDTHH:MM:SS[.ffffff]Z". Only run_upsert, story_upsert,
// subtask_upsert, phase_upsert and attempt_upsert give a row; every other event
// and every unknown payload key is ignored. Pure and never throwing; reads no
// clock and no time zone.

var _LEVELS = { run_upsert: "run", story_upsert: "story", subtask_upsert: "subtask",
                phase_upsert: "phase", attempt_upsert: "attempt" }

var _RUN_WORDS = { started: "started", done: "done", stopped: "paused", escalated: "escalated",
                   cancelled: "cancelled", canceled: "cancelled" }

var _TS_RE = /^\d{4}-\d{2}-\d{2}T(\d{2}):(\d{2}):(\d{2})(\.\d+)?Z$/

function _isObject(v) { return v !== null && typeof v === "object" && !Array.isArray(v) }
function _has(o, key) { return Object.prototype.hasOwnProperty.call(o, key) }
function _isFiniteNumber(v) { return typeof v === "number" && isFinite(v) }
function _stringOr(v) { return typeof v === "string" ? v : "" }
function _pad2(n) { return (n < 10 ? "0" : "") + n }

// "HH:MM:SS" of a UTC ts shifted by utcOffsetMinutes (0 when not a finite
// number, rounded to the minute) and wrapped into one day; the fraction is
// dropped. "" when ts is not "YYYY-MM-DDTHH:MM:SS[.f]Z".
function _timeOf(ts, utcOffsetMinutes) {
  var m = typeof ts === "string" ? _TS_RE.exec(ts) : null
  if (m === null) return ""
  var offset = _isFiniteNumber(utcOffsetMinutes) ? Math.round(utcOffsetMinutes) : 0
  var day = 86400
  var secs = Number(m[1]) * 3600 + Number(m[2]) * 60 + Number(m[3]) + offset * 60
  secs = (secs % day + day) % day
  return _pad2(Math.floor(secs / 3600)) + ":" + _pad2(Math.floor(secs % 3600 / 60)) + ":" + _pad2(secs % 60)
}

// titles[id] when titles is an object with that own key holding a non-empty
// string, else Runs.shortId of the id.
function _nameOf(id, titles) {
  if (_isObject(titles) && typeof id === "string" && _has(titles, id) && _stringOr(titles[id]) !== "")
    return titles[id]
  return Runs.shortId({ id: id })
}

function _labelOf(level, event, titles, status, phase, attempt) {
  if (level === "run") {
    if (status === "") return "run"
    return "run " + (_has(_RUN_WORDS, status) ? _RUN_WORDS[status] : status)
  }
  var name = _nameOf(level === "story" ? event.story : event.card, titles)
  if (level === "story" || level === "subtask" || phase === "") return name
  if (level === "phase" || attempt === 0) return name + " " + phase
  return name + " " + phase + "." + attempt
}

// One timeline row for an am journal event, or null when event is not an
// object or not one of the five *_upsert kinds. Row:
//   { seq, time, level, label, status, glyph, duration, detail, card, phase, attempt }
// seq: event.seq, else 0. time: "HH:MM:SS" of ts at utcOffsetMinutes, else "".
// level: run | story | subtask | phase | attempt. label: the node's title from
// titles (story id or card id -> title), else its short id; a phase adds
// " <phase>", an attempt " <phase>.<n>"; a run is "run <status word>".
// status: payload.status as written, else "". glyph: Runs.glyphStateOf(status).
// duration: an attempt's durationText(payload.duration), else "". detail: a
// phase's payload.detail, else "". card: event.card, else "". phase:
// event.phase, else a phase event's payload.name, else "". attempt: an
// attempt's event.attempt, else payload.n, when above 0; else 0.
function eventRow(event, titles, utcOffsetMinutes) {
  if (!_isObject(event) || typeof event.event !== "string" || !_has(_LEVELS, event.event)) return null
  var level = _LEVELS[event.event]
  var payload = _isObject(event.payload) ? event.payload : {}
  var status = _stringOr(payload.status)
  var phase = _stringOr(event.phase)
  if (phase === "" && level === "phase") phase = _stringOr(payload.name)
  var attempt = 0
  if (level === "attempt") {
    if (_isFiniteNumber(event.attempt) && event.attempt > 0) attempt = event.attempt
    else if (_isFiniteNumber(payload.n) && payload.n > 0) attempt = payload.n
  }
  return {
    seq: _isFiniteNumber(event.seq) ? event.seq : 0,
    time: _timeOf(event.ts, utcOffsetMinutes),
    level: level,
    label: _labelOf(level, event, titles, status, phase, attempt),
    status: status,
    glyph: Runs.glyphStateOf(status),
    duration: level === "attempt" ? durationText(payload.duration) : "",
    detail: level === "phase" ? _stringOr(payload.detail) : "",
    card: _stringOr(event.card),
    phase: phase,
    attempt: attempt
  }
}

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

var _DEFAULT_CAP = 500

function _isRow(v) { return _isObject(v) && _isFiniteNumber(v.seq) }

// Folds a page of rows (events) into the held rows: one row per seq, the last
// taken winning (rows first, then events, each in array order), ascending by
// seq, then the lowest seqs removed until at most cap remain. An entry counts
// only when it is a non-array object with a finite number seq; rows or events
// not an array read as []. cap: floored; 500 when missing, not a finite number
// or negative. Returns { rows, dropped }, dropped the count removed by the cap.
// Rows is a new array of the same entry objects; no input is modified.
function foldEvents(rows, events, cap) {
  var bySeq = {}
  var seqs = []
  var sources = [Array.isArray(rows) ? rows : [], Array.isArray(events) ? events : []]
  for (var s = 0; s < sources.length; s++) {
    for (var i = 0; i < sources[s].length; i++) {
      var row = sources[s][i]
      if (!_isRow(row)) continue
      var key = String(row.seq)
      if (!_has(bySeq, key)) seqs.push(row.seq)
      bySeq[key] = row
    }
  }
  seqs.sort(function (a, b) { return a - b })
  var limit = _isFiniteNumber(cap) && cap >= 0 ? Math.floor(cap) : _DEFAULT_CAP
  var dropped = Math.max(0, seqs.length - limit)
  var out = []
  for (var j = dropped; j < seqs.length; j++) out.push(bySeq[String(seqs[j])])
  return { rows: out, dropped: dropped }
}
