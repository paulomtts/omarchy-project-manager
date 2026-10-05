.pragma library

// What the run store says about one run's controls, read out of its maps with
// own-key checks: a run id such as `constructor` or `__proto__` is just an id
// with nothing pending. The screens pass the store's maps in from their own
// bindings, so every replacement of `pending` or `stillWaiting` re-runs them.

function runIdOf(run) {
  return run !== null && typeof run === "object" && typeof run.id === "string" ? run.id : ""
}

function _has(map, key) {
  return key !== "" && map !== null && typeof map === "object" && Object.prototype.hasOwnProperty.call(map, key)
}

// The action pending for the run ("pause" | "resume" | "cancel"), or "".
function pendingOf(pending, run) {
  var id = runIdOf(run)
  return _has(pending, id) && typeof pending[id] === "string" ? pending[id] : ""
}

// The run's pending request is 30 s or more old.
function waitingOf(stillWaiting, run) {
  var id = runIdOf(run)
  return _has(stillWaiting, id) && stillWaiting[id] === true
}

// The control error when it is about this run, else "".
function errorOf(errorText, errorRunId, run) {
  var id = runIdOf(run)
  return id !== "" && errorRunId === id && typeof errorText === "string" ? errorText : ""
}
