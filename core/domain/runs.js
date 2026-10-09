.pragma library
.import "board.js" as Board

// Run domain model: one `am` orchestrator run, normalised from the CLI's
// output.
//
// Input of normalizeRun:
//   raw = {
//     row:    one `am runs` entry without its `status`:
//             { id, workflow, repo_dir, base_branch, branch_prefix, status, started_at,
//               milestone_id, card_id, lease, progress, project: { id, repo_dir } }
//     status: `am status` data, may be absent:
//             { as_of_seq, store_id,
//               run: { id, workflow, repo_dir, base_branch, branch_prefix, status, started_at },
//               stories: [{ card_id, title, level, status, tip_branch,
//                           subtasks: [{ card_id, branch, base_branch, status, worktree_path,
//                                        phases: [{ name, kind, status, started_at, ended_at, detail,
//                                                   attempts: [{ n, status, ... }] }] }] }],
//               rows: [{ story, subtask, phase, attempt, state }],
//               control: { lease: { pid, host, heartbeat_at, accepting, live, ... },
//                          requests: [{ command, requested_at, handled_at }], claims },
//               integrity }
//   }
// Output scalars: id, repo_dir, started_at, base_branch, branch_prefix and
// workflow are the row's, else the am status run's; status and milestone_id are
// the am status run's, else the row's. `lease` keeps pid, host, heartbeat_at,
// accepting and live. `requests` are am's control requests in the order made;
// handled_at "" means the run has not acted on it yet.
// `project` is the row's { id, repo_dir }: id a finite number else null,
// repo_dir text. It is null when the row has no project object; am status
// never supplies it, and the run's repo_dir is independent of it.
// tree.stories: every object story in am's order, the synthetic `integrate` and
// `bases` included; its `subtasks` is the card_id strings of its subtasks.
// tree.subtasks: the subtasks of every other story, flattened in am's order,
// each with `story_id`, its story's card_id.
// rows: { story_id, card_id, phase, attempt, status } from am's story, subtask,
// phase, attempt and state, in am's order. A row under `integrate` or `bases`
// whose subtask is a real card id (an Integrate resolver) is dropped.
//
// as_of_seq and store_id are not kept: the store reads them. Keys not named
// here are ignored. Only `row` and `status` are read; it takes no events.
// The status always comes from `am`, never from a brd card. The output holds
// copies, never am's objects. Never throws: anything missing or malformed
// becomes its default, and a missing lease means the run is not live.
function normalizeRun(raw) {
  function isObject(v) { return v !== null && typeof v === "object" && !Array.isArray(v) }
  function objectOr(v) { return isObject(v) ? v : {} }
  function arrayOr(v) { return Array.isArray(v) ? v : [] }
  function text(v) { return v === undefined || v === null ? "" : String(v) }
  function firstText(a, b) { var s = text(a); return s !== "" ? s : text(b) }
  function asGiven(v) { return v === undefined || v === null ? "" : v }
  function stringOr(v) { return typeof v === "string" ? v : "" }
  function isSyntheticStory(id) { return id === "integrate" || id === "bases" }

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

  var project = null
  if (isObject(row.project)) {
    var p = row.project
    project = {
      id: typeof p.id === "number" && isFinite(p.id) ? p.id : null,
      repo_dir: text(p.repo_dir)
    }
  }

  var requests = []
  var rawRequests = arrayOr(control.requests)
  for (var i = 0; i < rawRequests.length; i++) {
    var q = rawRequests[i]
    if (!isObject(q)) continue
    requests.push({ command: text(q.command), requested_at: text(q.requested_at), handled_at: text(q.handled_at) })
  }

  var stories = [], subtasks = []
  var amStories = arrayOr(st.stories)
  for (var s = 0; s < amStories.length; s++) {
    var story = amStories[s]
    if (!isObject(story)) continue
    var real = !isSyntheticStory(story.card_id)
    var ids = []
    var amSubtasks = arrayOr(story.subtasks)
    for (var t = 0; t < amSubtasks.length; t++) {
      var subtask = amSubtasks[t]
      if (!isObject(subtask)) continue
      if (typeof subtask.card_id === "string") ids.push(subtask.card_id)
      if (!real) continue
      var copied = _copyOf(subtask)
      copied.story_id = stringOr(story.card_id)
      subtasks.push(copied)
    }
    var storyCopy = _copyOf(story)
    storyCopy.subtasks = ids
    stories.push(storyCopy)
  }

  var rows = []
  var amRows = arrayOr(st.rows)
  for (var w = 0; w < amRows.length; w++) {
    var amRow = amRows[w]
    if (!isObject(amRow)) continue
    if (isSyntheticStory(amRow.story) && _isCardId(amRow.subtask)) continue
    rows.push({
      story_id: stringOr(amRow.story),
      card_id: stringOr(amRow.subtask),
      phase: stringOr(amRow.phase),
      attempt: typeof amRow.attempt === "number" && isFinite(amRow.attempt) ? amRow.attempt : null,
      status: stringOr(amRow.state)
    })
  }

  return {
    id: firstText(row.id, run.id),
    repo_dir: firstText(row.repo_dir, run.repo_dir),
    milestone_id: firstText(run.milestone_id, row.milestone_id),
    status: firstText(run.status, row.status),
    started_at: firstText(row.started_at, run.started_at),
    base_branch: firstText(row.base_branch, run.base_branch),
    branch_prefix: firstText(row.branch_prefix, run.branch_prefix),
    workflow: firstText(row.workflow, run.workflow),
    lease: lease,
    project: project,
    requests: requests,
    rows: rows,
    tree: { stories: stories, subtasks: subtasks }
  }
}

// The one state shown for a normalised run. The lease matters only while the
// run says `started`: a started run whose lease is missing or not live is
// dead. Both `cancelled` and `canceled` are `cancelled`, whatever the lease.
// Anything else -- an unknown or empty status, or no run at all -- is
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
  if (status === "cancelled" || status === "canceled") return "cancelled"
  if (status === "escalated" || status === "done") return status
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

// A JSON-like deep copy of arrays and objects. An own `__proto__` key is
// dropped, so every copied object's prototype is Object.prototype.
function _copyOf(v) {
  if (Array.isArray(v)) {
    var list = []
    for (var a = 0; a < v.length; a++) list.push(_copyOf(v[a]))
    return list
  }
  if (!_isObject(v)) return v
  var out = {}
  var keys = Object.keys(v)
  for (var k = 0; k < keys.length; k++) {
    if (keys[k] !== "__proto__") out[keys[k]] = _copyOf(v[keys[k]])
  }
  return out
}

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

// Which subtask status lands in which rollup bucket; anything else is pending.
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

// Run-progress counts for a brd card: the winning run's real subtasks, one each, by the
// subtask's own status. Never rows, never brd status (Board.subtreeCounts is separate).
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
  var subtasks = _arrayOr(tree.subtasks)
  for (var i = 0; i < subtasks.length; i++) {
    var subtask = subtasks[i]
    if (!_isObject(subtask) || !_isCardId(subtask.card_id)) continue
    if (!isMilestone) {
      var belongs = story !== null ? _storyHas(story, subtask, cardId) : subtask.card_id === cardId
      if (!belongs) continue
    }
    counts[_bucketOf(subtask.status)] += 1
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

// `path` with every trailing "/" removed; a path of only slashes is "/". A
// non-string is "".
function _trimSlashes(path) {
  if (typeof path !== "string") return ""
  var end = path.length
  while (end > 0 && path.charAt(end - 1) === "/") end--
  if (end === 0) return path === "" ? "" : "/"
  return path.substring(0, end)
}

// A copy of `run` whose `project` is { root, name }, the registered project it
// belongs to; whatever `project` it held before is dropped. root: `root` with
// every trailing "/" removed ("/" for a root of only slashes), else "" when not
// a string; nothing else is normalised. name: `name` trimmed when that is
// non-empty, else root's last "/"-separated segment ("/" for "/", "" for "").
// The copy is deep and JSON-like (an own `__proto__` key is dropped). A `run`
// that is not a plain object is returned as is. Never mutates, never throws.
function withProject(run, root, name) {
  if (!_isObject(run)) return run
  var out = _copyOf(run)
  var r = _trimSlashes(root)
  var n = typeof name === "string" ? name.trim() : ""
  if (n === "") n = r === "/" ? "/" : r.substring(r.lastIndexOf("/") + 1)
  out.project = { root: r, name: n }
  return out
}

// The runs of the project at `root`: the entries whose `project.root` is a
// string equal to `root`, both compared with trailing "/" removed and otherwise
// exactly. A `root` of null, undefined or "" keeps every entry. Any other
// non-string `root`, or a `runs` that is not an array, gives []. Returns a new
// array of the same objects, input order. Never mutates, never throws.
function filterByProject(runs, root) {
  var list = _arrayOr(runs)
  if (root === null || root === undefined || root === "") return list.slice()
  if (typeof root !== "string") return []
  var want = _trimSlashes(root)
  var out = []
  for (var i = 0; i < list.length; i++) {
    var run = list[i]
    if (_isObject(run) && _isObject(run.project) && typeof run.project.root === "string" &&
        _trimSlashes(run.project.root) === want) out.push(run)
  }
  return out
}

// Order of two project groups: a group with attention > 0 first, then one with
// live > 0, then the rest; then project.name lower-cased, then project.root,
// both by plain string comparison. Roots are distinct, so no two groups tie.
function _compareGroups(a, b) {
  function rank(g) { return g.counts.attention > 0 ? 0 : (g.counts.live > 0 ? 1 : 2) }
  var ra = rank(a), rb = rank(b)
  if (ra !== rb) return ra - rb
  var na = a.project.name.toLowerCase(), nb = b.project.name.toLowerCase()
  if (na !== nb) return na < nb ? -1 : 1
  if (a.project.root !== b.project.root) return a.project.root < b.project.root ? -1 : 1
  return 0
}

// The runs grouped by registered project, in display order. Entries that are
// not plain objects are dropped. Each group is
//   { project: { root, name }, runs, counts: { live, parked, attention } }
// root: the entry's `project.root` with every trailing "/" removed ("/" for a
// root of only slashes), else "" when `project` is not a plain object or its
// root is not a string; otherwise compared exactly. name: the `project.name` of
// the group's first entry when a string, else ""; always "" for root "". runs:
// the same objects, input order.
// counts, by runState: live = running; parked = parked; attention = escalated
// or dead (the runs `attention` returns). A group exists only for a root some
// entry has. Order: groups with attention > 0, then live > 0, then the rest;
// ties by name lower-cased, then root, by plain string comparison. The root ""
// group is last, whatever its counts. A `runs` that is not an array gives [].
// Never mutates, never throws.
function groupByProject(runs) {
  var list = _arrayOr(runs)
  var groups = []
  var loose = null
  for (var i = 0; i < list.length; i++) {
    var run = list[i]
    if (!_isObject(run)) continue
    var project = _isObject(run.project) ? run.project : {}
    var root = typeof project.root === "string" ? _trimSlashes(project.root) : ""
    var group = root === "" ? loose : null
    for (var g = 0; root !== "" && group === null && g < groups.length; g++) {
      if (groups[g].project.root === root) group = groups[g]
    }
    if (group === null) {
      group = { project: { root: root, name: root === "" ? "" : _stringOr(project.name) },
                runs: [], counts: { live: 0, parked: 0, attention: 0 } }
      if (root === "") loose = group
      else groups.push(group)
    }
    group.runs.push(run)
    var s = runState(run)
    if (s === "running") group.counts.live += 1
    else if (s === "parked") group.counts.parked += 1
    else if (s === "escalated" || s === "dead") group.counts.attention += 1
  }
  groups.sort(_compareGroups)
  if (loose !== null) groups.push(loose)
  return groups
}

// The runs of `groups` (groupByProject output) as one list: each group's `runs`
// in turn, the same values in order. A group that is not a plain object, or
// whose `runs` is not an array, is skipped; a `groups` that is not an array
// gives []. Returns a new array. Never mutates, never throws.
function displayOrder(groups) {
  var list = _arrayOr(groups)
  var out = []
  for (var i = 0; i < list.length; i++) {
    var group = list[i]
    if (!_isObject(group) || !Array.isArray(group.runs)) continue
    for (var j = 0; j < group.runs.length; j++) out.push(group.runs[j])
  }
  return out
}

// String(v), trimmed. null/undefined, and values String() cannot convert (e.g. a
// prototype-less object), become "".
function _textOf(v) {
  if (v === undefined || v === null) return ""
  try { return String(v).trim() } catch (e) { return "" }
}

// Row statuses that mean a phase or attempt failed.
var _FAILURE_STATUSES = ["failed", "escalated", "gate_failed", "schema_invalid", "harness_error"]

// Why a run escalated: the first failed phase's detail (or its last attempt's detail),
// else "escalated at <that phase>". With no failed phase, "escalated at <phase>" of the
// last row whose status is failed, escalated, gate_failed, schema_invalid or
// harness_error and whose phase is not empty; else "escalated".
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
    var row = rows[r]
    if (!_isObject(row) || _FAILURE_STATUSES.indexOf(row.status) < 0) continue
    var at = _textOf(row.phase)
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

// Counts of the run's real subtasks (an object with a real card id) and of those whose own
// `status` is `done`.
function runProgress(run) {
  var subtasks = _subtasksOf(run)
  var done = 0, total = 0
  for (var i = 0; i < subtasks.length; i++) {
    var subtask = subtasks[i]
    if (!_isObject(subtask) || !_isCardId(subtask.card_id)) continue
    total += 1
    if (subtask.status === "done") done += 1
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

// The last `maxLines` lines of an `am logs` data object's
// artifacts.stdout.text, then the last `maxLines` of its artifacts.stderr.text,
// as one string. A missing artifact or a text that is not a string is no lines.
// `truncated` says lines were cut. A bad maxLines is 200.
function logTail(data, maxLines) {
  var max = _isFiniteNumber(maxLines) && maxLines >= 1 ? Math.floor(maxLines) : 200
  var artifacts = _isObject(data) && _isObject(data.artifacts) ? data.artifacts : {}
  var out = _isObject(artifacts.stdout) ? _linesOf(artifacts.stdout.text) : []
  var err = _isObject(artifacts.stderr) ? _linesOf(artifacts.stderr.text) : []
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
// or row status is drawn with: started is running; failed and the attempt
// failures gate_failed, schema_invalid, harness_error are dead; both cancelled
// and canceled are cancelled; the attempt outcome ok is done. "" for anything
// else, which shows no glyph.
function glyphStateOf(status) {
  if (status === "started" || status === "running") return "running"
  if (status === "stopped" || status === "parked") return "parked"
  if (status === "escalated") return "escalated"
  if (status === "failed" || status === "dead" || status === "gate_failed" ||
      status === "schema_invalid" || status === "harness_error") return "dead"
  if (status === "cancelled" || status === "canceled") return "cancelled"
  if (status === "done" || status === "ok") return "done"
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
// no number). The current phase is the first started one, else the last one
// with a numbered attempt, else the last; the current attempt is that phase's
// newest number, 0 when it has none.
function _subtaskNode(run, subtask) {
  var phases = [], attempts = []
  var started = null, numbered = null, last = null
  var list = _arrayOr(subtask.phases)
  for (var i = 0; i < list.length; i++) {
    var p = list[i]
    if (!_isObject(p) || typeof p.name !== "string" || p.name === "") continue
    phases.push({ name: p.name, status: _stringOr(p.status) })
    if (started === null && p.status === "started") started = p
    if (_newestAttempt(p) > 0) numbered = p
    last = p
    var tries = _arrayOr(p.attempts)
    for (var k = 0; k < tries.length; k++) {
      if (_isObject(tries[k])) attempts.push({ phase: p.name, attempt: _attemptNumber(tries[k]), status: _stringOr(tries[k].status) })
    }
  }
  var current = started !== null ? started : numbered !== null ? numbered : last
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


// ---- Dispatch (S3 1.1) -------------------------------------------------------------------
//
// What the dispatch dialog may start, and the form's starting values. Pure and
// never throwing, like the rest of this file. The one exception to "every input
// comes from am": these read a brd card as Board.indexTree() leaves it
// ({id, title, status, parentId, depth}) and its {id: card} cardMap. Ids are
// compared with === and looked up only as own keys of cardMap, so ids such as
// `__proto__` behave like any absent id.

var _DISPATCH_NO_CARD = "No card to dispatch"
var _DISPATCH_UNKNOWN_LEVEL = "The card's level is unknown"

// A card id am can take as a target: a non-empty string that cannot be read as a flag.
function _isDispatchId(id) { return typeof id === "string" && id !== "" && id.charAt(0) !== "-" }

// A finite number with no fractional part.
function _isWholeNumber(v) { return _isFiniteNumber(v) && Math.floor(v) === v }

// cardMap[id] when cardMap is an object that owns the string key id and the
// entry is an object, else null. Inherited keys never count.
function _ownCard(cardMap, id) {
  if (!_isObject(cardMap) || typeof id !== "string") return null
  if (!Object.prototype.hasOwnProperty.call(cardMap, id)) return null
  return _isObject(cardMap[id]) ? cardMap[id] : null
}

// A fresh plan the dialog may start.
function _offeredPlan(level, command, flags) {
  return { command: command, flags: flags, level: level, offered: true, reason: "", suggest: null }
}

// A fresh plan the dialog must refuse, with the sentence that says why.
function _refusedPlan(level, reason, suggest) {
  return { command: "", flags: [], level: level, offered: false, reason: reason, suggest: suggest }
}

// What the dispatch dialog may start for card. "board" is the whole board;
// otherwise card is a brd card: depth 0 milestone (--milestone), 1 story
// (--story), 2+ subtask (--card). A finished card is refused at every level.
// cardMap is accepted and not read. Decision order and sentences are pinned in
// docs/superpowers/specs/1-1-runs-js-5eb7ec0c.md and
// docs/superpowers/specs/1-2-runs-js-the-story-a2a74eda.md.
function dispatchPlan(card, cardMap) {
  if (card === "board") return _offeredPlan("board", "board", ["--board"])
  if (!_isObject(card) || !_isDispatchId(card.id)) return _refusedPlan("", _DISPATCH_NO_CARD, null)
  if (!_isWholeNumber(card.depth) || card.depth < 0) return _refusedPlan("", _DISPATCH_UNKNOWN_LEVEL, null)
  var level = card.depth === 0 ? "milestone" : (card.depth === 1 ? "story" : "subtask")
  if (Board.isFinishedStatus(card.status)) return _refusedPlan(level, "The card is " + card.status, null)
  if (level === "milestone") return _offeredPlan("milestone", "milestone", ["--milestone", card.id])
  if (level === "story") return _offeredPlan("story", "story", ["--story", card.id])
  return _offeredPlan("subtask", "card", ["--card", card.id])
}

// The milestone card whose title names the branch prefix: card itself at depth
// 0, else the first card with no parentId (null, undefined or "") reached by
// following parentId through cardMap's own keys. The walk trusts parentId, not
// depth. A missing link, a non-string parentId, a non-object entry or a cycle
// (an id seen twice) gives null, as does no cardMap.
function _milestoneOf(card, cardMap) {
  if (!_isObject(card)) return null
  if (card.depth === 0) return card
  if (!_isObject(cardMap)) return null
  var seen = []
  var current = card
  while (true) {
    var parentId = current.parentId
    if (parentId === null || parentId === undefined || parentId === "") return current
    if (seen.indexOf(parentId) >= 0) return null
    seen.push(parentId)
    current = _ownCard(cardMap, parentId)
    if (current === null) return null
  }
}


// The milestone {id, title}, fresh, of the card _milestoneOf reaches from
// card: card itself at depth 0, a story's parent, a subtask's root. null when
// the walk gives null, the card reached does not have depth exactly 0, or its
// id is not a dispatch id. title is the card's title when it is a string, else "".
function dispatchMilestone(card, cardMap) {
  var milestone = _milestoneOf(card, cardMap)
  if (milestone === null || milestone.depth !== 0 || !_isDispatchId(milestone.id)) return null
  return { id: milestone.id, title: _stringOr(milestone.title) }
}

// The dispatch dialog's target text: `Whole board` for "board"; `No card`
// for a non-object card or one without a dispatch id; else, with T the
// card's title (a string, else ""), `Milestone "T"` at depth 0, `Story "T"
// (milestone "M")` at depth 1 with M dispatchMilestone's title (`Story "T"`
// when it is null), `Subtask "T"` at a whole depth >= 2, and `"T"` for any
// other depth. The card's status is not read.
function dispatchLabel(card, cardMap) {
  if (card === "board") return "Whole board"
  if (!_isObject(card) || !_isDispatchId(card.id)) return "No card"
  var title = _stringOr(card.title)
  if (card.depth === 0) return "Milestone \"" + title + "\""
  if (card.depth === 1) {
    var milestone = dispatchMilestone(card, cardMap)
    return milestone !== null ? "Story \"" + title + "\" (milestone \"" + milestone.title + "\")" : "Story \"" + title + "\""
  }
  if (_isWholeNumber(card.depth) && card.depth >= 2) return "Subtask \"" + title + "\""
  return "\"" + title + "\""
}

// The branch-prefix stem of a milestone title: lower-case [a-z0-9] tokens; a
// first token like "m3" (letters then digits) is the stem, else the first three
// tokens joined by "-", cut to 24 characters, without a trailing "-".
function _stemOf(title) {
  var words = _textOf(title).split(/\s+/)
  var tokens = []
  for (var i = 0; i < words.length; i++) {
    var token = words[i].toLowerCase().replace(/[^a-z0-9]/g, "")
    if (token !== "") tokens.push(token)
  }
  if (tokens.length === 0) return ""
  if (/^[a-z]+[0-9]+$/.test(tokens[0])) return tokens[0]
  return tokens.slice(0, 3).join("-").slice(0, 24).replace(/-+$/, "")
}

// v trimmed when it is a string, else "".
function _trimmedOr(v) { return typeof v === "string" ? v.trim() : "" }

// The first entry of history that is a non-blank string, trimmed; "" when
// history is not an array or has none.
function _historyPrefix(history) {
  var list = _arrayOr(history)
  for (var i = 0; i < list.length; i++) {
    var prefix = _trimmedOr(list[i])
    if (prefix !== "") return prefix
  }
  return ""
}

// The trimmed branch_prefix of the newest run in runs (newest first, see
// _isNewer) whose milestone_id is key and whose branch_prefix is a non-blank
// string; "" when runs is not an array or has none.
function _runPrefix(runs, key) {
  var list = _arrayOr(runs)
  var newest = -1
  for (var i = 0; i < list.length; i++) {
    var run = list[i]
    if (!_isObject(run) || run.milestone_id !== key || _trimmedOr(run.branch_prefix) === "") continue
    if (newest < 0 || _isNewer(run, i, list[newest], newest)) newest = i
  }
  return newest < 0 ? "" : _trimmedOr(list[newest].branch_prefix)
}

// map's own entry for key, trimmed, when map is an object and the entry a
// string; else "". Inherited keys never count.
function _mapPrefix(map, key) {
  if (!_isObject(map) || !Object.prototype.hasOwnProperty.call(map, key)) return ""
  return _trimmedOr(map[key])
}

// The prefix default for milestone (a card, or null when the card's milestone
// is unknown): "" for null; else the first non-blank of, in order, the newest
// run of the milestone (_runPrefix), settings.prefixByMilestone's own entry for
// the milestone's id (both only when that id is a non-empty string), the first
// prefix of settings.prefixHistory, and the stem of milestone's title.
function _defaultPrefix(milestone, settings, runs) {
  if (milestone === null) return ""
  var key = milestone.id
  if (typeof key === "string" && key !== "") {
    var fromRun = _runPrefix(runs, key)
    if (fromRun !== "") return fromRun
    var fromMap = _mapPrefix(settings.prefixByMilestone, key)
    if (fromMap !== "") return fromMap
  }
  var fromHistory = _historyPrefix(settings.prefixHistory)
  return fromHistory !== "" ? fromHistory : _stemOf(milestone.title)
}

// The dispatch form's starting values. project is {defaultBranch, settings}
// with settings as get-run-settings returns it; runs is the Runs snapshot
// (normalizeRun output, newest first), [] when not an array; any part may be
// missing. base is the trimmed default branch (no fallback: the caller
// resolves it). prefix is "" when the card's milestone is unknown, else the
// first non-blank, trimmed, of: the branch_prefix of the newest run whose
// milestone_id is the milestone's id; settings.prefixByMilestone's own entry
// for that id; the first entry of settings.prefixHistory; the stem of the
// milestone's title. verify is the stored non-blank commands verbatim,
// parallelism the stored whole number >= 1 else 4. The opt-out from
// verification is never pre-ticked.
function dispatchDefaults(project, card, cardMap, runs) {
  var p = _isObject(project) ? project : {}
  var settings = _isObject(p.settings) ? p.settings : {}
  var milestone = _milestoneOf(card, cardMap)
  var stored = _arrayOr(settings.verify)
  var verify = []
  for (var i = 0; i < stored.length; i++) {
    if (typeof stored[i] === "string" && stored[i].trim() !== "") verify.push(stored[i])
  }
  var parallelism = settings.parallelism
  return {
    allowNoVerification: false,
    base: typeof p.defaultBranch === "string" ? _textOf(p.defaultBranch) : "",
    parallelism: _isWholeNumber(parallelism) && parallelism >= 1 ? parallelism : 4,
    prefix: _defaultPrefix(milestone, settings, runs),
    verify: verify
  }
}


// ---- Dispatch form and preview (S3 1.2) --------------------------------------------------
//
// The dispatch form's own checks, and the one-line summary of an `am run
// --dry-run` payload (the envelope's data, milestone, story or board). Pure and
// never throwing, like the rest of this file. Rules, sentences and payload
// shapes are pinned in docs/superpowers/specs/1-2-runs-js-45cc9067.md and
// docs/superpowers/specs/1-2-runs-js-the-story-a2a74eda.md.

var _DISPATCH_PREFIX_EMPTY = "Enter a branch prefix"
var _DISPATCH_VERIFY_MISSING = "Add a verify command or choose to run without verification"
var _DISPATCH_PARALLELISM_INVALID = "Parallelism must be a whole number of at least 1"

// A fresh form error.
function _formError(field, message) { return { field: field, message: message } }

// The form's failed rules, in order prefix, verify, parallelism; ok when none
// failed. form has dispatchDefaults' keys; a non-object form is read as {}.
// prefix must be a non-blank string; verify needs one non-blank string command
// unless allowNoVerification is exactly true; parallelism must be a whole
// number >= 1. base is not checked: am refuses a bad one through the preview.
function validateDispatch(form) {
  var f = _isObject(form) ? form : {}
  var errors = []
  if (typeof f.prefix !== "string" || f.prefix.trim() === "") errors.push(_formError("prefix", _DISPATCH_PREFIX_EMPTY))
  var commands = _arrayOr(f.verify)
  var count = 0
  for (var i = 0; i < commands.length; i++) {
    if (typeof commands[i] === "string" && commands[i].trim() !== "") count++
  }
  if (count === 0 && f.allowNoVerification !== true) errors.push(_formError("verify", _DISPATCH_VERIFY_MISSING))
  if (!(_isWholeNumber(f.parallelism) && f.parallelism >= 1)) errors.push(_formError("parallelism", _DISPATCH_PARALLELISM_INVALID))
  return { errors: errors, ok: errors.length === 0 }
}


// "<n> <singular>" when n is exactly 1, else "<n> <plural>".
function _countOf(n, singular, plural) { return n + " " + (n === 1 ? singular : plural) }

// The object entries of list, fresh; [] when list is not an array.
function _objectsOf(list) {
  var a = _arrayOr(list)
  var out = []
  for (var i = 0; i < a.length; i++) {
    if (_isObject(a[i])) out.push(a[i])
  }
  return out
}

// How many subtasks a milestone dry-run plan would dispatch: the object entries
// of levels[].stories[].subtasks, skipping non-object levels and stories. A
// non-object plan, and already_done, count nothing.
function _planSubtasks(plan) {
  if (!_isObject(plan)) return 0
  var count = 0
  var levels = _objectsOf(plan.levels)
  for (var i = 0; i < levels.length; i++) {
    var stories = _objectsOf(levels[i].stories)
    for (var j = 0; j < stories.length; j++) count += _objectsOf(stories[j].subtasks).length
  }
  return count
}

// The fresh result for a payload previewSummary cannot read.
function _unreadablePreview() { return { board: false, integrate: "", summary: "" } }

// The first object subtask of a dry-run plan, walking object levels, then
// object stories, then object subtasks, in order; null when there is none.
function _firstPlanSubtask(plan) {
  var levels = _objectsOf(plan.levels)
  for (var i = 0; i < levels.length; i++) {
    var stories = _objectsOf(levels[i].stories)
    for (var j = 0; j < stories.length; j++) {
      var subtasks = _objectsOf(stories[j].subtasks)
      if (subtasks.length > 0) return subtasks[0]
    }
  }
  return null
}

// The story preview of a readable `am run --story --dry-run` payload: "<S>
// subtask(s)", then " \u00b7 rooted on <base>" when the first object subtask's
// base is a non-blank string (trimmed); "Nothing left to run" when S is 0.
// integrate, already_done and board are not read.
function _storyPreview(plan) {
  var count = _planSubtasks(plan)
  if (count === 0) return { board: false, integrate: "", summary: "Nothing left to run" }
  var first = _firstPlanSubtask(plan)
  var base = first !== null && typeof first.base === "string" ? _textOf(first.base) : ""
  var summary = _countOf(count, "subtask", "subtasks")
  if (base !== "") summary += " \u00b7 rooted on " + base
  return { board: false, integrate: "", summary: summary }
}

// The dispatch dialog's preview lines for `am run --dry-run` data (never the
// {ok, data} envelope). level is the target's level: exactly "story" gives the
// story preview ("<S> subtask(s) \u00b7 rooted on <base>", or "Nothing left to
// run"; never an Integrate line, a done count or board true). Any other level
// reads the payload: a board payload (board exactly true) gives "<N>
// milestone(s), <M> subtask(s)" and no Integrate line; a milestone payload
// gives "<L> level(s) \u00b7 <S> subtask(s)", then " \u00b7 <D> stor(y|ies) already
// done" when D > 0, and "Integrate \u2192 <branch>" when integrate.branch is a
// non-blank string. Only subtasks listed in levels count. No array levels
// means unreadable at every level: board false and both lines "".
function previewSummary(dryRunData, level) {
  if (!_isObject(dryRunData) || !Array.isArray(dryRunData.levels)) return _unreadablePreview()
  if (level === "story") return _storyPreview(dryRunData)
  var levels = _objectsOf(dryRunData.levels)
  if (dryRunData.board === true) {
    var milestones = 0
    var boardSubtasks = 0
    for (var i = 0; i < levels.length; i++) {
      var entries = _objectsOf(levels[i].milestones)
      milestones += entries.length
      for (var j = 0; j < entries.length; j++) boardSubtasks += _planSubtasks(entries[j].plan)
    }
    return {
      board: true,
      integrate: "",
      summary: _countOf(milestones, "milestone", "milestones") + ", " + _countOf(boardSubtasks, "subtask", "subtasks")
    }
  }
  var summary = _countOf(levels.length, "level", "levels") + " \u00b7 " +
                _countOf(_planSubtasks(dryRunData), "subtask", "subtasks")
  var finished = _objectsOf(dryRunData.already_done)
  var done = 0
  for (var k = 0; k < finished.length; k++) {
    if (finished[k].kind === "story") done++
  }
  if (done > 0) summary += " \u00b7 " + _countOf(done, "story", "stories") + " already done"
  var integrate = dryRunData.integrate
  var branch = _isObject(integrate) && typeof integrate.branch === "string" ? _textOf(integrate.branch) : ""
  return { board: false, integrate: branch !== "" ? "Integrate \u2192 " + branch : "", summary: summary }
}
