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
