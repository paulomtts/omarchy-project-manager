.pragma library

// Run domain model: one `am` orchestrator run, normalised from the CLI's
// output.
//
// Input shape for normalizeRun (provisional until the runs-snapshot helper
// exists; pinned by tests/core/domain/tst_runs.qml):
//   raw = {
//     row:    { id, workflow, repo_dir, base_branch, branch_prefix, status, started_at }  // one `am runs` row
//     status: { run: {...}, rows: [...], stories: [...], subtasks: [...],
//               control: { lease: { pid, host, heartbeat_at, accepting, live } }, ... }  // `am status` data, may be absent
//   }
//
// The status always comes from `am` (am status first, then the am runs row),
// never from a brd card. Never throws: anything missing or malformed becomes
// its default, and a missing lease means the run is not live.
function normalizeRun(raw) {
  function isObject(v) { return v !== null && typeof v === "object" && !Array.isArray(v) }
  function objectOr(v) { return isObject(v) ? v : {} }
  function arrayOr(v) { return Array.isArray(v) ? v : [] }
  function text(v) { return v === undefined || v === null ? "" : String(v) }
  function firstText(a, b) { var s = text(a); return s !== "" ? s : text(b) }
  function asGiven(v) { return v === undefined || v === null ? "" : v }

  var r = objectOr(raw)
  var row = objectOr(r.row)
  var st = objectOr(r.status)
  var run = objectOr(st.run)
  var control = objectOr(st.control)

  var lease = null
  if (isObject(control.lease)) {
    var l = control.lease
    lease = {
      pid: asGiven(l.pid),
      host: asGiven(l.host),
      heartbeat_at: asGiven(l.heartbeat_at),
      accepting: l.accepting === true,
      live: l.live === true
    }
  }

  return {
    id: firstText(row.id, run.id),
    repo_dir: firstText(row.repo_dir, run.repo_dir),
    milestone_id: firstText(run.milestone_id, row.milestone_id),
    status: firstText(run.status, row.status),
    started_at: firstText(row.started_at, run.started_at),
    lease: lease,
    rows: arrayOr(st.rows),
    tree: { stories: arrayOr(st.stories), subtasks: arrayOr(st.subtasks) }
  }
}

// The one state shown for a normalised run. The lease matters only while the
// run says `started`: a started run whose lease is missing or not live is
// dead. Anything else -- an unknown or empty status, or no run at all -- is
// `unknown`, which is neither running nor finished. `stale` is a card state,
// never a run state.
function runState(run) {
  if (run === null || typeof run !== "object") return "unknown"
  var status = run.status
  if (status === "started") {
    var lease = run.lease
    return lease !== null && typeof lease === "object" && lease.live === true ? "running" : "dead"
  }
  if (status === "stopped") return "parked"
  if (status === "escalated" || status === "cancelled" || status === "done") return status
  return "unknown"
}

// ---- Card mapping, rollups, attention, error text (1.2) ----------------------------------
//
// Inputs are normalised runs (normalizeRun output), taken newest first. None of
// these functions reads brd status, and none throws: garbage becomes the
// default. Card ids are compared with === on strings by linear scan, so ids such
// as `__proto__` or `constructor` behave like any other id.

function _isObject(v) { return v !== null && typeof v === "object" && !Array.isArray(v) }
function _arrayOr(v) { return Array.isArray(v) ? v : [] }
function _stringOr(v) { return typeof v === "string" ? v : "" }
function _isFiniteNumber(v) { return typeof v === "number" && isFinite(v) }
function _treeOf(run) { return _isObject(run) && _isObject(run.tree) ? run.tree : {} }
function _lastOf(list) { var a = _arrayOr(list); return a.length > 0 ? a[a.length - 1] : null }

// `integrate`, `bases` and `base-*` are orchestrator bookkeeping ids, never cards.
function _isSynthetic(id) {
  return id === "integrate" || id === "bases" || (typeof id === "string" && id.indexOf("base-") === 0)
}

function _isCardId(id) { return typeof id === "string" && id !== "" && !_isSynthetic(id) }

function _findByCardId(list, cardId) {
  var items = _arrayOr(list)
  for (var i = 0; i < items.length; i++) {
    if (_isObject(items[i]) && items[i].card_id === cardId) return items[i]
  }
  return null
}

// A run touches a card through its milestone, a story or a subtask -- never through rows alone.
function _touches(run, cardId) {
  if (!_isObject(run)) return false
  if (run.milestone_id === cardId) return true
  var tree = _treeOf(run)
  return _findByCardId(tree.stories, cardId) !== null || _findByCardId(tree.subtasks, cardId) !== null
}

// Non-terminal = status `started` (live or dead). Everything else is finished or unknown.
function _isNonTerminal(run) {
  var s = runState(run)
  return s === "running" || s === "dead"
}

// Is run a (at index ai) newer than run b (at index bi)? A later started_at wins when both
// carry a distinct non-empty string; otherwise the earlier index (input is newest first).
function _isNewer(a, ai, b, bi) {
  var as = _stringOr(a.started_at), bs = _stringOr(b.started_at)
  if (as !== "" && bs !== "" && as !== bs) return as > bs
  return ai < bi
}

// The run that speaks for a card: newest non-terminal run touching it, else the newest run
// touching it (dimmed). null when nothing touches it or the id is not a real card id.
function _winningRun(runs, cardId) {
  if (!_isCardId(cardId)) return null
  var list = _arrayOr(runs)
  var best = null, bestIndex = -1, bestLive = false
  for (var i = 0; i < list.length; i++) {
    var run = list[i]
    if (!_touches(run, cardId)) continue
    var live = _isNonTerminal(run)
    if (best === null || (live && !bestLive) || (live === bestLive && _isNewer(run, i, best, bestIndex))) {
      best = run
      bestIndex = i
      bestLive = live
    }
  }
  return best === null ? null : { run: best, dimmed: !bestLive }
}

// The am run state of one card, separate from its brd status.
// state: running | dead | parked | escalated | none. phase/attempt only for a subtask card.
function cardRunState(runs, cardId) {
  var result = { state: "none", runId: "", dimmed: false, phase: "", attempt: 0 }
  var win = _winningRun(runs, cardId)
  if (win === null) return result
  var s = runState(win.run)
  result.state = s === "running" || s === "dead" || s === "parked" || s === "escalated" ? s : "none"
  result.runId = _stringOr(win.run.id)
  result.dimmed = win.dimmed
  var subtask = _findByCardId(_treeOf(win.run).subtasks, cardId)
  var phase = subtask === null ? null : _lastOf(subtask.phases)
  if (_isObject(phase)) {
    result.phase = _stringOr(phase.name)
    var attempts = _arrayOr(phase.attempts)
    result.attempt = attempts.length
    var last = _lastOf(attempts)
    if (_isObject(last)) {
      if (_isFiniteNumber(last.attempt)) result.attempt = last.attempt
      else if (_isFiniteNumber(last.n)) result.attempt = last.n
    }
  }
  return result
}

// Which am row status lands in which rollup bucket; anything else is pending.
function _bucketOf(status) {
  if (status === "running" || status === "started") return "running"
  if (status === "parked" || status === "stopped") return "parked"
  if (status === "escalated" || status === "failed") return "escalated"
  if (status === "done") return "done"
  return "pending"
}

// Does the story own this subtask? Via the subtask's story_id, or the story's own list
// (entries are id strings or {card_id}).
function _storyHas(story, subtask, storyId) {
  if (subtask.story_id === storyId) return true
  var entries = _arrayOr(story.subtasks)
  for (var i = 0; i < entries.length; i++) {
    var e = entries[i]
    if (e === subtask.card_id || (_isObject(e) && e.card_id === subtask.card_id)) return true
  }
  return false
}

// Run-progress counts for a brd card, from the winning run's am rows only (never brd status;
// Board.subtreeCounts is a separate thing). Only rows of real subtasks in that run count.
function rollup(runs, card) {
  var counts = { running: 0, parked: 0, escalated: 0, done: 0, pending: 0, total: 0 }
  if (!_isObject(card)) return counts
  var cardId = card.id
  var win = _winningRun(runs, cardId)
  if (win === null) return counts
  var run = win.run
  var tree = _treeOf(run)
  var isMilestone = run.milestone_id === cardId
  var story = isMilestone ? null : _findByCardId(tree.stories, cardId)
  var rows = _arrayOr(run.rows)
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i]
    if (!_isObject(row) || !_isCardId(row.card_id)) continue
    var subtask = _findByCardId(tree.subtasks, row.card_id)
    if (subtask === null) continue
    if (!isMilestone) {
      var belongs = story !== null ? _storyHas(story, subtask, cardId) : row.card_id === cardId
      if (!belongs) continue
    }
    counts[_bucketOf(row.status)] += 1
    counts.total += 1
  }
  return counts
}

// Runs that need a human: escalated, or started with a dead lease. Same objects, input order.
function attention(runs) {
  var list = _arrayOr(runs)
  var out = []
  for (var i = 0; i < list.length; i++) {
    var s = runState(list[i])
    if (s === "escalated" || s === "dead") out.push(list[i])
  }
  return out
}

// String(v), trimmed. null/undefined, and values String() cannot convert (e.g. a
// prototype-less object), become "".
function _textOf(v) {
  if (v === undefined || v === null) return ""
  try { return String(v).trim() } catch (e) { return "" }
}

// Why a run escalated: the first failed phase's detail (or its last attempt's detail),
// else "escalated at <phase>", else "escalated".
function escalationReason(run) {
  var subtasks = _arrayOr(_treeOf(run).subtasks)
  for (var i = 0; i < subtasks.length; i++) {
    var phases = _isObject(subtasks[i]) ? _arrayOr(subtasks[i].phases) : []
    for (var j = 0; j < phases.length; j++) {
      var phase = phases[j]
      if (!_isObject(phase) || phase.status !== "failed") continue
      var detail = _textOf(phase.detail)
      var attempts = _arrayOr(phase.attempts)
      for (var k = attempts.length - 1; detail === "" && k >= 0; k--) {
        if (_isObject(attempts[k])) detail = _textOf(attempts[k].detail)
      }
      if (detail !== "") return detail
      var name = _textOf(phase.name)
      return name !== "" ? "escalated at " + name : "escalated"
    }
  }
  var rows = _isObject(run) ? _arrayOr(run.rows) : []
  for (var r = rows.length - 1; r >= 0; r--) {
    var at = _isObject(rows[r]) ? _textOf(rows[r].phase) : ""
    if (at !== "") return "escalated at " + at
  }
  return "escalated"
}

// Display text for an am error: the {ok:false, error:{type, message}} envelope or the bare
// {type, message}. "type: message", either alone, or "unknown error". ok:true gives "".
function errorText(error) {
  if (!_isObject(error)) return "unknown error"
  if (error.ok === true) return ""
  var e = _isObject(error.error) ? error.error : error
  var type = _textOf(e.type)
  var message = _textOf(e.message)
  if (type !== "" && message !== "") return type + ": " + message
  if (type !== "") return type
  if (message !== "") return message
  return "unknown error"
}

// ---- Runs screen (5.1) -------------------------------------------------------------------
//
// What one row of the Runs screen shows, and the chip filters and the search
// over the list. Pure and never throwing, like the rest of this file.

function _subtasksOf(run) { return _arrayOr(_treeOf(run).subtasks) }

// "…" and the last 8 characters of the id (all of a shorter one); "…" alone
// when the id is not a string.
function shortId(run) {
  var id = _isObject(run) ? run.id : undefined
  return typeof id === "string" ? "…" + id.slice(-8) : "…"
}

// The run's milestone, else its short id.
function runTitle(run) {
  var milestone = _isObject(run) ? _stringOr(run.milestone_id) : ""
  return milestone !== "" ? milestone : shortId(run)
}

// How many of the run's subtasks are through. A subtask is done when it has
// phases and every one of them is `done`; only object subtasks count at all.
function runProgress(run) {
  var subtasks = _subtasksOf(run)
  var done = 0, total = 0
  for (var i = 0; i < subtasks.length; i++) {
    if (!_isObject(subtasks[i])) continue
    total += 1
    var phases = _arrayOr(subtasks[i].phases)
    var allDone = phases.length > 0
    for (var j = 0; allDone && j < phases.length; j++) allDone = _isObject(phases[j]) && phases[j].status === "done"
    if (allDone) done += 1
  }
  return { done: done, total: total }
}

// The name of the first `started` phase, in subtask order; "" when none is.
function currentPhase(run) {
  var subtasks = _subtasksOf(run)
  for (var i = 0; i < subtasks.length; i++) {
    var phases = _isObject(subtasks[i]) ? _arrayOr(subtasks[i].phases) : []
    for (var j = 0; j < phases.length; j++) {
      if (!_isObject(phases[j]) || phases[j].status !== "started") continue
      var name = _textOf(phases[j].name)
      if (name !== "") return name
    }
  }
  return ""
}

// How long ago an ISO time was, without "ago": "just now" under a minute, then
// "Nm", "Nh" or "Nd". "" for an empty, unparsable or future time, or a clock
// that is not a finite number.
function ageText(iso, nowMs) {
  if (typeof iso !== "string" || iso === "" || !_isFiniteNumber(nowMs)) return ""
  var t = Date.parse(iso)
  if (!isFinite(t)) return ""
  var diff = nowMs - t
  if (diff < 0) return ""
  if (diff < 60000) return "just now"
  if (diff < 3600000) return Math.floor(diff / 60000) + "m"
  if (diff < 86400000) return Math.floor(diff / 3600000) + "h"
  return Math.floor(diff / 86400000) + "d"
}

// A row's age: since the last heartbeat for a dead run ("" with no lease),
// since it started for every other state.
function runAgeText(run, nowMs) {
  if (runState(run) === "dead") return _isObject(run.lease) ? ageText(run.lease.heartbeat_at, nowMs) : ""
  return ageText(_isObject(run) ? run.started_at : "", nowMs)
}

function _withState(list, state) {
  var out = []
  for (var i = 0; i < list.length; i++) if (runState(list[i]) === state) out.push(list[i])
  return out
}

// The chip counts, over every run (the search never narrows them).
function runFilterCounts(runs) {
  var list = _arrayOr(runs)
  return {
    attention: attention(list).length,
    live: _withState(list, "running").length,
    parked: _withState(list, "parked").length,
    all: list.length
  }
}

// One chip's runs, same objects in input order. `all`, "" or any unknown id is
// every run.
function filterRuns(runs, id) {
  var list = _arrayOr(runs)
  if (id === "attention") return attention(list)
  if (id === "live") return _withState(list, "running")
  if (id === "parked") return _withState(list, "parked")
  return list
}

// Case-insensitive substring match on the id, title, current phase and state
// name. An empty (or all-space) query returns the input itself.
function searchRuns(runs, q) {
  var list = _arrayOr(runs)
  if (typeof q !== "string" || q.trim() === "") return list
  var needle = q.trim().toLowerCase()
  var out = []
  for (var i = 0; i < list.length; i++) {
    var run = list[i]
    if (!_isObject(run)) continue
    var hay = [_stringOr(run.id), runTitle(run), currentPhase(run), runState(run)].join("\n").toLowerCase()
    if (hay.indexOf(needle) >= 0) out.push(run)
  }
  return out
}
