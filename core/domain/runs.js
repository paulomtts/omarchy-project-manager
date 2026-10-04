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
    base_branch: firstText(row.base_branch, run.base_branch),
    branch_prefix: firstText(row.branch_prefix, run.branch_prefix),
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

// Every run that touches a card (through its milestone, a story or a subtask --
// never through rows alone), as the same objects in input order: am's order,
// newest first. [] for anything that is not a real card id, or for garbage runs.
function runsTouching(runs, cardId) {
  if (!_isCardId(cardId)) return []
  var list = _arrayOr(runs)
  var out = []
  for (var i = 0; i < list.length; i++) {
    if (_touches(list[i], cardId)) out.push(list[i])
  }
  return out
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

// ---- Run detail (5.2) --------------------------------------------------------------------
//
// The Run detail screen's tree, the attempt its output pane opens on, one
// attempt's status, the tail of an `am logs` snapshot and that snapshot's age.
// Pure and never throwing, like the rest of this file. The tree is read in the
// shape the functions above read: flat tree.stories[] and tree.subtasks[], each
// keyed by card_id; phases are { name, status, detail?, attempts[] } and
// attempts { n | attempt, status }.

// A text's lines without the one trailing newline; [] for "" or a non-string.
function _linesOf(text) {
  if (typeof text !== "string" || text === "") return []
  var t = text.charAt(text.length - 1) === "\n" ? text.slice(0, -1) : text
  return t === "" ? [] : t.split("\n")
}

// The last `maxLines` lines of an `am logs` data object's stdout, then the last
// `maxLines` of its stderr, as one string. `truncated` says lines were cut, so
// the pane can say "last 200 lines". A bad maxLines is 200.
function logTail(data, maxLines) {
  var max = _isFiniteNumber(maxLines) && maxLines >= 1 ? Math.floor(maxLines) : 200
  var out = _isObject(data) ? _linesOf(data.stdout) : []
  var err = _isObject(data) ? _linesOf(data.stderr) : []
  var truncated = out.length > max || err.length > max
  if (out.length > max) out = out.slice(out.length - max)
  if (err.length > max) err = err.slice(err.length - max)
  return { text: out.concat(err).join("\n"), truncated: truncated }
}

// How old a logs snapshot is, without "ago": "Ns" under a minute, then "Nm",
// "Nh" or "Nd". "" for a fetch time that is missing (0 or less), not finite or
// in the future, or a clock that is not a finite number.
function snapshotAgeText(fetchedMs, nowMs) {
  if (!_isFiniteNumber(fetchedMs) || fetchedMs <= 0 || !_isFiniteNumber(nowMs)) return ""
  var diff = nowMs - fetchedMs
  if (diff < 0) return ""
  if (diff < 60000) return Math.floor(diff / 1000) + "s"
  if (diff < 3600000) return Math.floor(diff / 60000) + "m"
  if (diff < 86400000) return Math.floor(diff / 3600000) + "h"
  return Math.floor(diff / 86400000) + "d"
}

// The run-state name (a runGlyphs.js key) an am story, subtask, phase, attempt
// or row status is drawn with -- the mapping PhaseTimeline uses (started is
// running, failed is dead). "" for anything else, which shows no glyph.
function glyphStateOf(status) {
  if (status === "started" || status === "running") return "running"
  if (status === "stopped" || status === "parked") return "parked"
  if (status === "escalated") return "escalated"
  if (status === "failed" || status === "dead") return "dead"
  if (status === "cancelled") return "cancelled"
  if (status === "done") return "done"
  return ""
}

// An attempt's number: `attempt`, else `n`, when a finite number above 0; else
// 0, an attempt `am logs` cannot be asked about.
function _attemptNumber(a) {
  if (!_isObject(a)) return 0
  if (_isFiniteNumber(a.attempt) && a.attempt > 0) return a.attempt
  if (_isFiniteNumber(a.n) && a.n > 0) return a.n
  return 0
}

// The highest attempt number of a phase; 0 when it has no numbered attempt.
function _newestAttempt(phase) {
  var attempts = _isObject(phase) ? _arrayOr(phase.attempts) : []
  var best = 0
  for (var i = 0; i < attempts.length; i++) best = Math.max(best, _attemptNumber(attempts[i]))
  return best
}

// The subtask's first phase with this name, or null.
function _findPhase(subtask, name) {
  if (!_isObject(subtask) || typeof name !== "string" || name === "") return null
  var phases = _arrayOr(subtask.phases)
  for (var i = 0; i < phases.length; i++) {
    if (_isObject(phases[i]) && phases[i].name === name) return phases[i]
  }
  return null
}

// The status of the last am row for an id; "" when there is none.
function _lastRowStatus(run, id) {
  var rows = _isObject(run) ? _arrayOr(run.rows) : []
  for (var i = rows.length - 1; i >= 0; i--) {
    if (_isObject(rows[i]) && rows[i].card_id === id) return _stringOr(rows[i].status)
  }
  return ""
}

function _syntheticLabel(id) {
  if (id === "integrate") return "Integrate"
  if (id === "bases") return "Bases"
  return id.length > 5 ? "Base " + id.slice(5) : "Base"
}

// One subtask as the detail tree shows it. Its own status, else its last am
// row's; phases with a name only; every attempt object (attempt 0 when it has
// no number); the current phase is the first started one, else the last.
function _subtaskNode(run, subtask) {
  var phases = [], attempts = []
  var started = null, last = null
  var list = _arrayOr(subtask.phases)
  for (var i = 0; i < list.length; i++) {
    var p = list[i]
    if (!_isObject(p) || typeof p.name !== "string" || p.name === "") continue
    phases.push({ name: p.name, status: _stringOr(p.status) })
    if (started === null && p.status === "started") started = p
    last = p
    var tries = _arrayOr(p.attempts)
    for (var k = 0; k < tries.length; k++) {
      if (_isObject(tries[k])) attempts.push({ phase: p.name, attempt: _attemptNumber(tries[k]), status: _stringOr(tries[k].status) })
    }
  }
  var current = started !== null ? started : last
  var own = _stringOr(subtask.status)
  return {
    card_id: subtask.card_id,
    status: own !== "" ? own : _lastRowStatus(run, subtask.card_id),
    phases: phases,
    attempts: attempts,
    currentPhase: current === null ? "" : current.name,
    currentAttempt: _newestAttempt(current)
  }
}

// The Run detail tree: the run's stories in am's order, each with the subtasks
// it owns (a subtask goes to the first story that owns it), then an "Other"
// group for subtasks of no story. Bookkeeping ids (integrate, bases, base-*)
// from the stories, the subtasks or the rows become labelled rows of their own,
// only when present. Never throws.
function runTree(run) {
  var tree = _treeOf(run)
  var stories = _arrayOr(tree.stories), subtasks = _arrayOr(tree.subtasks)
  var synthetic = [], seen = []
  function addSynthetic(id, status) {
    if (seen.indexOf(id) >= 0) return
    seen.push(id)
    var own = _stringOr(status)
    synthetic.push({ id: id, label: _syntheticLabel(id), status: own !== "" ? own : _lastRowStatus(run, id) })
  }
  var realStories = [], realSubtasks = []
  for (var i = 0; i < stories.length; i++) {
    var s = stories[i]
    if (!_isObject(s)) continue
    if (_isSynthetic(s.card_id)) addSynthetic(s.card_id, s.status)
    else if (_isCardId(s.card_id)) realStories.push(s)
  }
  for (var j = 0; j < subtasks.length; j++) {
    var t = subtasks[j]
    if (!_isObject(t)) continue
    if (_isSynthetic(t.card_id)) addSynthetic(t.card_id, t.status)
    else if (_isCardId(t.card_id)) realSubtasks.push(t)
  }
  var rows = _isObject(run) ? _arrayOr(run.rows) : []
  for (var r = 0; r < rows.length; r++) {
    if (_isObject(rows[r]) && _isSynthetic(rows[r].card_id)) addSynthetic(rows[r].card_id, "")
  }
  var claimed = [], out = []
  for (var si = 0; si < realStories.length; si++) {
    var story = realStories[si]
    var mine = []
    for (var ti = 0; ti < realSubtasks.length; ti++) {
      if (claimed.indexOf(ti) >= 0 || !_storyHas(story, realSubtasks[ti], story.card_id)) continue
      claimed.push(ti)
      mine.push(_subtaskNode(run, realSubtasks[ti]))
    }
    var ownStatus = _stringOr(story.status)
    out.push({ card_id: story.card_id, label: story.card_id,
               status: ownStatus !== "" ? ownStatus : _lastRowStatus(run, story.card_id), other: false, subtasks: mine })
  }
  var others = []
  for (var oi = 0; oi < realSubtasks.length; oi++) {
    if (claimed.indexOf(oi) < 0) others.push(_subtaskNode(run, realSubtasks[oi]))
  }
  if (others.length > 0) out.push({ card_id: "", label: "Other", status: "", other: true, subtasks: others })
  return { stories: out, synthetic: synthetic }
}

// The attempt the output pane opens on: the newest numbered attempt of the
// first started phase (in subtask order) that has one; else, walking the flat
// rows from the last, the newest attempt of a real card's row phase (the row's
// own number or the tree's, whichever is higher); else null.
function defaultAttempt(run) {
  var subtasks = _subtasksOf(run)
  for (var i = 0; i < subtasks.length; i++) {
    var t = subtasks[i]
    if (!_isObject(t) || !_isCardId(t.card_id)) continue
    var phases = _arrayOr(t.phases)
    for (var j = 0; j < phases.length; j++) {
      var p = phases[j]
      if (!_isObject(p) || p.status !== "started" || typeof p.name !== "string" || p.name === "") continue
      var n = _newestAttempt(p)
      if (n > 0) return { card_id: t.card_id, phase: p.name, attempt: n }
    }
  }
  var rows = _isObject(run) ? _arrayOr(run.rows) : []
  for (var r = rows.length - 1; r >= 0; r--) {
    var row = rows[r]
    if (!_isObject(row) || !_isCardId(row.card_id)) continue
    var phase = _stringOr(row.phase)
    if (phase === "") continue
    var newest = Math.max(_attemptNumber(row), _newestAttempt(_findPhase(_findByCardId(subtasks, row.card_id), phase)))
    if (newest > 0) return { card_id: row.card_id, phase: phase, attempt: newest }
  }
  return null
}

// One attempt's status from the run's tree; "" when it is not there.
function attemptStatus(run, cardId, phase, attempt) {
  if (!_isCardId(cardId) || !_isFiniteNumber(attempt) || attempt <= 0) return ""
  var p = _findPhase(_findByCardId(_subtasksOf(run), cardId), phase)
  var tries = _isObject(p) ? _arrayOr(p.attempts) : []
  for (var i = tries.length - 1; i >= 0; i--) {
    if (_attemptNumber(tries[i]) === attempt) return _stringOr(tries[i].status)
  }
  return ""
}

// ---- Run controls (S2 1.1) ---------------------------------------------------------------
//
// Which of pause / resume / cancel a run allows, and the sentence for an am
// control error. Pure and never throwing, like the rest of this file. Whether a
// request is already outstanding is the store's business, not these functions'.

var _REASON_INTEGRATE = "Integrate is running; it cannot be paused or cancelled"
var _REASON_FINISHED = "The run has finished"
var _REASON_UNKNOWN = "The run's state is unknown"
var _REASON_PAUSE_NOT_RUNNING = "Only a running run can be paused"
var _REASON_RESUME_RUNNING = "The run is still running"
var _REASON_RESUME_CANCELLED = "A cancelled run cannot be resumed"
var _REASON_CANCEL_CANCELLED = "The run is already cancelled"

// A fresh {enabled, reason}: enabled exactly when there is no reason.
function _action(reason) { return { enabled: reason === "", reason: reason } }

// Integrate: the run holds a lease (an object) that is not accepting requests.
// With no lease, accepting is unknown, so the run is not treated as in Integrate.
function _inIntegrate(run) {
  return _isObject(run) && _isObject(run.lease) && run.lease.accepting !== true
}

// {pause, resume, cancel}, each a fresh {enabled, reason}; reason is "" when
// enabled. Pause needs a running run outside Integrate; resume needs dead,
// parked or escalated and never looks at accepting; cancel needs a run that has
// not finished and is not in Integrate. The state's reason wins over Integrate's.
function controls(run) {
  var state = runState(run)
  var integrate = _inIntegrate(run)
  var pause, resume, cancel
  if (state === "running") {
    pause = integrate ? _REASON_INTEGRATE : ""
    resume = _REASON_RESUME_RUNNING
    cancel = integrate ? _REASON_INTEGRATE : ""
  } else if (state === "dead" || state === "parked" || state === "escalated") {
    pause = _REASON_PAUSE_NOT_RUNNING
    resume = ""
    cancel = integrate ? _REASON_INTEGRATE : ""
  } else if (state === "cancelled") {
    pause = _REASON_FINISHED
    resume = _REASON_RESUME_CANCELLED
    cancel = _REASON_CANCEL_CANCELLED
  } else if (state === "done") {
    pause = _REASON_FINISHED
    resume = _REASON_FINISHED
    cancel = _REASON_FINISHED
  } else {
    pause = _REASON_UNKNOWN
    resume = _REASON_UNKNOWN
    cancel = _REASON_UNKNOWN
  }
  return { pause: _action(pause), resume: _action(resume), cancel: _action(cancel) }
}

// [type, sentence] for each am control error, matched with === by linear scan so
// a type such as `constructor` or `__proto__` is just an unknown type.
var _CONTROL_ERRORS = [
  ["UnknownRunError", "The run no longer exists"],
  ["NotRunningError", "The run is not running"],
  ["DeadRunError", "The run's process has died; resume it instead"],
  ["NotAcceptingError", _REASON_INTEGRATE],
  ["RunIsLiveError", "The run is still live; only a dead run can be resumed"],
  ["NotResumableError", "The run cannot be resumed"],
  ["ClaimedError", "Another run has already claimed this work"],
  ["LockTimeoutError", "am is busy; try again in a moment"]
]

// The sentence for a failed pause / resume / cancel. Reads the type the way
// errorText does (envelope or bare, trimmed, case-sensitive); a known type gives
// its sentence without am's message, anything else gives errorText(error).
function controlError(error) {
  if (_isObject(error) && error.ok !== true) {
    var e = _isObject(error.error) ? error.error : error
    var type = _textOf(e.type)
    for (var i = 0; i < _CONTROL_ERRORS.length; i++) {
      if (_CONTROL_ERRORS[i][0] === type) return _CONTROL_ERRORS[i][1]
    }
  }
  return errorText(error)
}


// ---- Run alerts (S2 1.2) -----------------------------------------------------------------
//
// Which runs newly need a human between two snapshots, for the toast and the
// desktop notification. Pure and never throwing, like the rest of this file.
// Keeping the previous snapshot (and resetting it to null) is the store's job.

var _REASON_DEAD = "process died"

// A run id a run can be matched by: a non-empty string.
function _isRunId(id) { return typeof id === "string" && id !== "" }

// runState of the first object run in list with this id, or "" when there is
// none. Linear === scan, so ids such as `__proto__` match like any other id.
function _previousState(list, id) {
  for (var i = 0; i < list.length; i++) {
    if (_isObject(list[i]) && list[i].id === id) return runState(list[i])
  }
  return ""
}

// Has an alert for this id already been raised in this call?
function _hasAlert(alerts, id) {
  for (var i = 0; i < alerts.length; i++) {
    if (alerts[i].id === id) return true
  }
  return false
}

// One fresh {id, title, state, reason} for each run in nextRuns, in its order,
// that is now escalated or dead and was not in that same state in prevRuns (a
// run absent from prevRuns was neither). A non-array prevRuns -- null is the
// store's "no previous snapshot" -- or nextRuns gives []. At most one alert per
// id; the first prevRuns occurrence of an id is its previous state. A dead
// run's reason is always "process died".
function newAlerts(prevRuns, nextRuns) {
  if (!Array.isArray(prevRuns) || !Array.isArray(nextRuns)) return []
  var out = []
  for (var i = 0; i < nextRuns.length; i++) {
    var run = nextRuns[i]
    if (!_isObject(run) || !_isRunId(run.id)) continue
    var state = runState(run)
    if (state !== "escalated" && state !== "dead") continue
    if (_previousState(prevRuns, run.id) === state) continue
    if (_hasAlert(out, run.id)) continue
    out.push({
      id: run.id,
      title: runTitle(run),
      state: state,
      reason: state === "dead" ? _REASON_DEAD : escalationReason(run)
    })
  }
  return out
}