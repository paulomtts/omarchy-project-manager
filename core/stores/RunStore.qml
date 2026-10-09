import QtQml
import Quickshell
import Quickshell.Io
import "../domain/runs.js" as Runs

// The am run monitor's data. One list snapshot covers every registered
// project: runs-snapshot-all.py with each usable root of `projectRoots`, in
// registry order. `runsByProject` holds each root's runs, normalized by the
// run domain model and tagged with their project; `projectErrors` the roots
// whose latest entry failed; `runs` every root's runs merged in registry
// order, a run id listed once, under the first root that lists it. A project
// switch leaves the run list alone: `project`, the open project, decides only
// the run settings and the dispatch; the run controls and the attempt logs
// act on each run's own repo_dir and project root. Plus the selected run, the
// attempt the Run detail pane shows and that
// attempt's `am logs` snapshot (runs-logs.py), and whether `am` could be
// asked at all. One list snapshot is in flight at a time, plus at most one
// pending request (requestSnapshot): a request never stops the snapshot in
// flight, and when that one ends its reply is applied and the pending
// request launches. While `active` (the panel is open) a long-lived
// runs-watch.py, given every usable root that begins with "/" and every
// known run id (startWatch), nudges it, "run X changed at seq N", and is
// never folded into state: once per debounce window the nudged run ids are
// announced (runsNudged) and the roots that list them are snapshotted, or
// every root when one id is unknown. A cursorReset hello starts over from a
// list snapshot, as does a hello naming a store_id other than the one last
// seen (storeId); the first store_id seen resets nothing. watchCursor is
// the watch's last cursor, held in memory only. Logs are fetched on a
// selection, on Refresh and when a snapshot changes the selected attempt's
// status -- never on a timer.
// Pause, resume and cancel (control()) each get a HelperRunner of their own.
// Dispatch (openDispatch .. dispatchStart) previews a run with
// dispatch-preview.py and starts it with start-run.py, one HelperRunner per
// Start.
// The registry, the open project's root and the backend directory are handed
// to it from outside -- it never reaches for another store. App composes it
// as `app.runs` and binds `active` to the panel being open.
Scope {
  id: store

  property var projectRoots: []       // [{root, name}], the registry in its order; App binds it
  property string project: ""         // the open project's root path; "" when none is open
  property string backendDir: ""      // <plugin>/core/backend/
  property bool active: false         // App binds this to "panel open" (app.panelOpen)

  // Each usable root's runs, {root: runs[]}: am's order, each run
  // Runs.withProject(Runs.normalizeRun(..), root, name). One key per usable
  // root a reply has covered.
  property var runsByProject: ({})
  // {root: Runs.errorText sentence} for each usable root whose latest entry failed.
  property var projectErrors: ({})
  // runsByProject's lists over the usable roots in registry order, a run id
  // an earlier root lists dropped from a later one.
  property var runs: []
  property string selectedRunId: ""   // set by the UI
  property string amStatus: "ok"      // "ok" | "missing" | "schema" | "error"
  property int amSchema: 0            // journal schema from the current watch's hello; 0 = unknown
  property string amVersion: ""       // am's version from the current watch's hello; "" = unknown
  property string lastError: ""
  property bool stale: false          // the last good snapshot is over 30 s old while active
  property string watchWarning: ""    // the corrupt-journal chip; "" when there is none

  // The Runs screen's chip ("" means All, else "attention" | "live" | "parked")
  // and search text. App binds searchQuery to the navigation store; the chip
  // survives a section switch and a project switch.
  property string runFilter: ""
  property string searchQuery: ""
  // The chip changed: a different list, so the cursor goes home (App's job).
  signal runFilterToggled()
  // The Runs screen's project filter: "" is All projects, else a filterable
  // root (isFilterable). Set by toggleProjectFilter; back to "" when it stops
  // being filterable (keepProjectFilter) and when the panel closes. A project
  // switch keeps it. Never persisted.
  property string projectFilter: ""
  // The project filter's list changed under the cursor: emitted once per
  // toggleProjectFilter call and once per fallback to All.
  signal projectFilterToggled()
  // The runs past the chip, the search and the project filter, grouped by
  // project in display order (Runs.groupByProject).
  readonly property var groups: Runs.groupByProject(Runs.filterByProject(Runs.searchRuns(Runs.filterRuns(store.runs, store.runFilter), store.searchQuery), store.projectFilter))
  // The one filtered list: the screen's rows and the navigator's cursor list,
  // group by group (Runs.displayOrder of groups).
  readonly property var filteredRuns: Runs.displayOrder(store.groups)

  // Snapshot coverage. `asOfSeq` is 0: the list snapshot names no as_of_seq.
  // `appliedSeq` is {runId: 0} for every run in `runs`: the run ids the store
  // knows. Both are replaced, never changed in place.
  property int asOfSeq: 0
  property var appliedSeq: ({})
  // The current watch's last {"cursor": C} (0 = none), held in memory only.
  property int watchCursor: 0
  // {runId: seq}: the highest changed seq per run since the last debounce
  // trigger. Replaced, never changed in place.
  property var nudges: ({})
  // am's store_id from the last watch hello that named one; "" = none yet.
  // Replaced, never derived. A project switch, the watch ending and AmMissing
  // keep it.
  property string storeId: ""

  // A watch has been started (or found no root to watch) since the last
  // activation: a later good snapshot starts another only while the watch
  // runs and the usable "/" roots changed (the helper picks up a watched
  // root's new runs itself), and a watch that ended is not restarted until
  // the next activation.
  property bool watchTried: false
  property int watchSeq: 0            // bumped on every watch start and stop: the launch guard
  property string watchSchemaError: "" // the schema banner text while its fallback poll runs

  // The Run detail pane (5.2): which attempt of the selected run it shows and
  // that attempt's last `am logs` snapshot. Never a live tail.
  property var selectedAttempt: null  // { card_id, phase, attempt } or null
  property string logsText: ""        // Runs.logTail of the last good reply
  property bool logsTruncated: false  // lines were cut from it
  property real logsFetchedMs: 0      // Date.now() when that reply landed; 0 before any
  property bool logsLoading: false    // a fetch is in flight
  property string logsError: ""       // why the last fetch failed; "" after a good one
  property string logsStatus: ""      // the attempt's status when its fetch was launched
  property string logsRunState: ""    // the run's Runs.runState when its opening attempt was chosen; "" when not in the snapshot

  // Run controls (S2 4.1). `pending` holds the requests not yet settled,
  // {runId: action}; `stillWaiting` the pending ones 30 s or more old,
  // {runId: true}. Both are replaced, never changed in place, so bindings see
  // every change. The control error is its own pair of fields: a snapshot never
  // touches it, and the snapshot's lastError never carries a control refusal.
  property var pending: ({})
  property var stillWaiting: ({})
  readonly property string stillWaitingText: "still waiting — the run may be between phases or dead"
  property string lastControlError: ""      // Runs.controlError sentence of the last failed request
  property string lastControlErrorRunId: "" // the run that sentence is about
  property string lastControlErrorType: ""  // am's error type of that failure; "" when it carried none

  // The cancel confirmation (S2 4.3). Panel renders it; the store keeps the
  // run it asks about ("" = closed), the typed word and why the last confirm
  // was refused.
  property string cancelRunId: ""
  readonly property bool cancelOpen: store.cancelRunId !== ""
  property string cancelText: ""
  property string cancelError: ""
  // The footer flash: why a run key was refused. flashTimer clears it.
  property string flashText: ""

  // Alerts (S2 4.4): a toast for every run of any registered project that
  // newly needs a human while the panel is open. `armedRoots` is {root: true}
  // of every usable root whose runs may be compared against, and is replaced,
  // never changed in place: a root's first good entry after an opening, a
  // store change, an am-missing spell or its return to the registry only arms
  // it, so history is never replayed. `alertsArmed`: some root is armed.
  // `toasts` is {key, id, title, state, reason, project, expiresMs}, oldest
  // first, at most 3, and is replaced, never changed in place; `project` is
  // the name of the run's project.
  property var armedRoots: ({})
  readonly property bool alertsArmed: Object.keys(store.armedRoots).length > 0
  property var toasts: []
  property int toastMs: 8000
  // "Notify on escalation", viewer-wide and off until read: the switch's
  // value, the last value read from or written to viewer-state.py's global
  // settings, and whether the user changed it since this opening's load was
  // launched (a late load reply then changes nothing). A project switch
  // never changes them.
  property bool notifyOnEscalation: false
  property bool notifySaved: false
  property bool notifyTouched: false
  // The open project's last get-run-settings object (runSettingsRunner), as
  // it was read: {} until its reply, when the reply is unreadable, and after
  // a project switch. The dispatch form starts from it; its
  // notifyOnEscalation is never read.
  property var runSettings: ({})

  // Dispatch (S3 3.1): starting an am run. The UI opens it for a target
  // (openDispatch), edits the form (setDispatchField) and presses Start
  // (dispatchStart); the store checks the form, previews it with
  // dispatch-preview.py and starts it with start-run.py. `dispatchState` is
  // idle | previewing | ready | refused | starting | started | failed. Every
  // object here is replaced, never changed in place.
  property string dispatchState: "idle"
  property var dispatchTarget: null     // Runs.dispatchPlan of the opened target; null while idle
  property string dispatchTargetLabel: "" // Runs.dispatchLabel of the opened target; "" while idle
  property var dispatchForm: null       // {base, prefix, verify, parallelism, allowNoVerification}; null while idle
  property var dispatchPreview: null    // Runs.previewSummary of the latest good preview
  property string dispatchError: ""     // the sentence for refused / failed
  property string dispatchErrorType: "" // am's or the helper's error.type, "Form", "Target" or ""
  property var dispatchErrors: []       // Runs.validateDispatch errors of a form refusal
  property var dispatchSuggest: null    // a blocked story's milestone {id, title}, which retargetToMilestone() opens; else null
  property string dispatchRunId: ""     // the started run's id; "" when none (yet)
  property string dispatchMessage: ""   // start-run.py's message after a start
  property string dispatchLog: ""       // a failed start's log path
  property string dispatchLogTail: ""   // the end of that log
  property var dispatchExitCode: null   // a failed start's exit code, when a number
  // A start for the current project went: the run id, or null while am does
  // not list it yet.
  signal dispatchStarted(var runId)
  // A debounce window's nudged run ids, each once, in first-nudge order,
  // known to the store or not. Never for a snapshot the store started itself.
  // (`runs` already owns the runsChanged name.)
  signal runsNudged(var ids)

  readonly property alias watching: watchState.watching   // the footer's "watching"
  readonly property alias watchProc: watchState.proc      // the current watch Process, or null
  readonly property alias watchRoots: watchState.roots    // the roots the current watch was launched with
  readonly property alias snapshotRunner: snapshotRunner
  readonly property alias snapshotRoots: snapshotState.roots     // the roots of the snapshot in flight; [] when idle
  readonly property alias pendingSnapshot: snapshotState.pending // the pending request: null, "all" or [root, ...]

  readonly property alias debounceTimer: debounceTimer
  readonly property alias livenessTimer: livenessTimer
  readonly property alias staleTimer: staleTimer
  readonly property alias pollTimer: pollTimer
  readonly property alias logsRunner: logsRunner
  readonly property alias controlRunners: controlState.runners  // in-flight control requests, oldest first
  readonly property alias pendingTimer: pendingTimer
  readonly property alias flashTimer: flashTimer
  readonly property alias toastTimer: toastTimer
  readonly property alias settingsLoadRunner: settingsLoadRunner
  readonly property alias settingsSaveRunner: settingsSaveRunner
  readonly property alias runSettingsRunner: runSettingsRunner
  readonly property alias notifyRunners: notifyState.runners    // in-flight notify.py launches, oldest first
  readonly property alias dispatchDefaultsRunner: dispatchDefaultsRunner
  readonly property alias dispatchPreviewRunner: dispatchPreviewRunner
  readonly property alias dispatchDebounceTimer: dispatchDebounceTimer
  readonly property alias dispatchStartRunners: dispatchBook.runners // in-flight start runners, oldest first

  // Some run is started with a live lease: its heartbeat must be re-read even
  // when the journal is quiet.
  readonly property bool hasRunningRun: {
    var list = store.runs
    for (var i = 0; i < list.length; i++) {
      if (Runs.runState(list[i]) === "running") return true
    }
    return false
  }

  // Requests a list snapshot of every usable root (requestSnapshot("all")),
  // whether or not a project is open. With no usable root nothing is
  // launched, the snapshot in flight is stopped, the pending request is
  // dropped, and the run list, runsByProject and projectErrors are emptied.
  function refresh() {
    if (store.usableRoots().length === 0) {
      store.dropSnapshots()
      store.runs = []
      store.runsByProject = {}
      store.projectErrors = {}
      return
    }
    store.requestSnapshot("all")
  }

  // Asks for a list snapshot of `roots` ([root, ...]) or of "all" roots. An
  // idle runner launches it at once (launchSnapshot). A busy one is never
  // stopped: the request joins the one pending request, "all" winning over
  // any roots, else the union of the roots.
  function requestSnapshot(roots) {
    if (!snapshotRunner.busy) {
      store.launchSnapshot(roots)
      return
    }
    var pending = snapshotState.pending
    if (pending === "all" || roots === "all") {
      snapshotState.pending = "all"
      return
    }
    var next = pending === null ? [] : pending.slice()
    for (var i = 0; i < roots.length; i++) {
      if (next.indexOf(roots[i]) < 0) next.push(roots[i])
    }
    snapshotState.pending = next
  }

  // runs-snapshot-all.py with the requested roots that are usable now, in
  // registry order, each once ("all": every usable root). None: nothing.
  function launchSnapshot(roots) {
    var usable = store.usableRoots()
    var list = []
    for (var i = 0; i < usable.length; i++) {
      if (roots === "all" || roots.indexOf(usable[i].root) >= 0) list.push(usable[i].root)
    }
    if (list.length === 0) return
    snapshotState.roots = list
    snapshotRunner.run(list)
  }

  // The snapshot in flight is stopped (its late exit changes nothing) and
  // the pending request is dropped.
  function dropSnapshots() {
    if (snapshotRunner.busy) snapshotRunner.cancel()
    snapshotState.roots = []
    snapshotState.pending = null
  }

  // The snapshot ended: its reply is applied, whatever it was, then the
  // pending request, if any, is launched against the registry as it is now.
  function snapshotEnded(stdout, exitCode) {
    var launched = snapshotState.roots
    snapshotState.roots = []
    store.applySnapshot(stdout, exitCode, launched)
    var next = snapshotState.pending
    snapshotState.pending = null
    if (next !== null) store.launchSnapshot(next)
  }

  // A chip was chosen: the All chip, or the active one again, means All.
  function toggleRunFilter(id) {
    store.runFilter = id === "all" || id === store.runFilter ? "" : String(id || "")
    store.runFilterToggled()
  }

  // A project chip was chosen (projectRootOf(root)): "", or the active
  // project again, means All; a root that is not filterable means All.
  // Emits projectFilterToggled once, whether or not the filter changed.
  function toggleProjectFilter(root) {
    var want = store.projectRootOf(root)
    var next = want === "" || want === store.projectFilter ? "" : want
    store.projectFilter = store.isFilterable(next) ? next : ""
    store.projectFilterToggled()
  }

  // `root` as Runs.withProject tags it: every trailing "/" removed, "/" for a
  // root of only slashes; "" for "" and for anything that is not a string.
  function projectRootOf(root) {
    return Runs.withProject({}, root, "").project.root
  }

  // Whether the project filter may hold `root`: it is not "", it is
  // projectRootOf a usable root, and some run in `runs` has it as
  // project.root.
  function isFilterable(root) {
    if (typeof root !== "string" || root === "") return false
    var usable = store.usableRoots()
    var registered = false
    for (var i = 0; i < usable.length && !registered; i++) {
      if (store.projectRootOf(usable[i].root) === root) registered = true
    }
    if (!registered) return false
    var list = store.runs
    for (var j = 0; j < list.length; j++) {
      var run = list[j]
      var p = run !== null && typeof run === "object" ? run.project : null
      if (p !== null && typeof p === "object" && p.root === root) return true
    }
    return false
  }

  // `runs` changed (a reply, a registry change, emptying, starting over): a
  // project filter that is no longer filterable becomes "" and
  // projectFilterToggled is emitted once; otherwise nothing happens.
  function keepProjectFilter() {
    if (store.projectFilter === "" || store.isFilterable(store.projectFilter)) return
    store.projectFilter = ""
    store.projectFilterToggled()
  }

  onRunsChanged: store.keepProjectFilter()

  onActiveChanged: {
    if (store.active) store.startLive()
    else store.stopLive()
  }

  // The panel opened: fetch now and read the notify switch (get-global-settings;
  // notifyTouched is cleared first unless a save is in flight); the first good
  // snapshot starts the watch and arms every root that answers in it, and the
  // stale clock counts from now.
  function startLive() {
    store.watchTried = false
    store.armedRoots = {}
    if (!settingsSaveRunner.busy) store.notifyTouched = false
    settingsLoadRunner.run(["get-global-settings"])
    store.restartStale()
    store.refresh()
  }

  // The panel closed: no process and no timer is left running, and no toast
  // or dispatch outlives the opening (a start in flight runs to its end). The
  // pending snapshot request is dropped; a snapshot in flight runs to its end
  // and is applied. The project filter is back to All projects, with no
  // projectFilterToggled. The runs, the selection, the chip and amStatus stay
  // for the next opening.
  function stopLive() {
    store.projectFilter = ""
    snapshotState.pending = null
    store.stopWatch()
    debounceTimer.stop()
    store.nudges = {}
    store.stopPoll()
    staleTimer.stop()
    store.stale = false
    store.watchWarning = ""
    store.armedRoots = {}
    store.toasts = []
    // A start in flight refuses and lands normally.
    store.closeDispatch()
  }

  // Nothing is stale yet; the 30 s clock starts again while the panel is open.
  function restartStale() {
    store.stale = false
    if (store.active) staleTimer.restart()
    else staleTimer.stop()
  }

  // No watch is left running, so am's schema and version are unknown again.
  function stopWatch() {
    store.watchSeq += 1
    if (watchState.proc) watchState.proc.running = false
    watchState.watching = false
    store.forgetHello()
  }

  // runs-watch.py ROOT... RUN...: the usable roots that begin with "/"
  // (watchableRoots), then the known run ids (knownRunIds), from now. No
  // root: no watch is launched, and watchTried keeps later snapshots from
  // trying again. Long-lived, so a plain Process rather than the
  // HelperRunner. It starts with am's schema and version unknown until its
  // own hello.
  function startWatch() {
    store.watchSeq += 1
    store.watchTried = true
    store.forgetHello()
    var roots = store.watchableRoots()
    if (roots.length === 0) return
    var proc = watchC.createObject(store, { launchSeq: store.watchSeq })
    proc.command = ["python3", store.backendDir + "runs/runs-watch.py"].concat(roots, store.knownRunIds())
    watchState.proc = proc
    watchState.roots = roots
    watchState.watching = true
    proc.running = true
  }

  // The usable roots, in registry order, that begin with "/": runs-watch.py
  // reads any other argument as a run id.
  function watchableRoots() {
    return store.usableRoots().map(function(p) { return p.root }).filter(function(root) {
      return root.charAt(0) === "/"
    })
  }

  // Every run id the usable roots' runsByProject lists hold, in registry
  // order then list order, each once. An id that is empty or begins with "-"
  // or "/" is left out: runs-watch.py refuses or misreads it.
  function knownRunIds() {
    var usable = store.usableRoots()
    var out = []
    var seen = {}
    for (var i = 0; i < usable.length; i++) {
      var list = store.hasKey(store.runsByProject, usable[i].root) ? store.runsByProject[usable[i].root] : []
      for (var j = 0; j < list.length; j++) {
        var run = list[j]
        var id = run !== null && typeof run === "object" && typeof run.id === "string" ? run.id : ""
        if (id === "" || id.charAt(0) === "-" || id.charAt(0) === "/" || store.hasKey(seen, id)) continue
        seen[id] = true
        out.push(id)
      }
    }
    return out
  }

  // Two root lists hold the same roots, whatever their order.
  function sameRoots(a, b) {
    if (a.length !== b.length) return false
    for (var i = 0; i < a.length; i++) {
      if (b.indexOf(a[i]) < 0) return false
    }
    return true
  }

  // A line or exit counts only from the newest launch: a watch that was
  // stopped (the panel closed) may still print or exit late. Which project
  // is open does not matter.
  function isCurrentWatch(proc) {
    return proc.launchSeq === store.watchSeq
  }

  // One stdout line of the watch, a nudge source never folded into state.
  // {"changed": [{run, seq}, ...]} records each nudge (recordNudges).
  // {"ok": false, ...} is kept as the envelope its exit explains. The hello,
  // {"hello": {"schema": N, "am": V, "head": H, "cursorReset": B,
  // "storeId": S}}, sets amSchema to N (an integer of 1 or more, else 0) and
  // amVersion to V (a string, else ""), and records S (seeStore). B === true,
  // or an S naming another store than the one last seen, starts over
  // (resetCursor) once; anything else starts nothing. H is not read.
  // {"cursor": C} sets watchCursor when C is an integer of 0 or more.
  // Anything else -- blank, not JSON, not an object, a hello that is not an
  // object -- is ignored. Never throws.
  function watchLine(proc, data) {
    if (!store.isCurrentWatch(proc)) return
    var text = String(data || "").trim()
    if (text === "") return
    var value = null
    try { value = JSON.parse(text) } catch (e) { return }
    if (value === null || typeof value !== "object" || Array.isArray(value)) return
    if (Array.isArray(value.changed)) store.recordNudges(value.changed)
    else if (value.ok === false) proc.envelope = value
    else if (value.hello !== null && typeof value.hello === "object" && !Array.isArray(value.hello)) {
      var schema = value.hello.schema
      store.amSchema = typeof schema === "number" && Number.isInteger(schema) && schema >= 1 ? schema : 0
      store.amVersion = typeof value.hello.am === "string" ? value.hello.am : ""
      var changed = store.seeStore(value.hello.storeId)
      if (changed || value.hello.cursorReset === true) store.resetCursor()
    } else if (store.hasKey(value, "cursor")) {
      if (store.isSeq(value.cursor)) store.watchCursor = value.cursor
    }
  }

  // A changed line's entries: each {run: non-empty string, seq: integer of 1
  // or more} raises nudges[run] to seq; every other entry is ignored. The
  // debounce restarts when at least one entry was recorded.
  function recordNudges(entries) {
    var next = null
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i]
      if (e === null || typeof e !== "object" || Array.isArray(e)) continue
      if (typeof e.run !== "string" || e.run === "" || !store.isSeq(e.seq) || e.seq < 1) continue
      if (next === null) next = store.copyMap(store.nudges)
      if (!store.hasKey(next, e.run) || next[e.run] < e.seq) next[e.run] = e.seq
    }
    if (next === null) return
    store.nudges = next
    debounceTimer.restart()
  }

  // The debounce fired: the nudges are taken and, when there were any, their
  // run ids are announced once (runsNudged), then one snapshot is requested:
  // of every root when an id is listed by no usable root, else of every
  // usable root whose runsByProject list holds one of the ids. The seqs gate
  // nothing.
  function triggerNudges() {
    var ids = Object.keys(store.nudges)
    store.nudges = {}
    if (ids.length === 0) return
    store.runsNudged(ids)
    var usable = store.usableRoots()
    var roots = []
    for (var i = 0; i < ids.length; i++) {
      var listed = false
      for (var j = 0; j < usable.length; j++) {
        if (!store.listsRun(usable[j].root, ids[i])) continue
        listed = true
        if (roots.indexOf(usable[j].root) < 0) roots.push(usable[j].root)
      }
      if (!listed) {
        store.refresh()
        return
      }
    }
    store.requestSnapshot(roots)
  }

  // root's runsByProject list holds a run with this id.
  function listsRun(root, id) {
    var list = store.hasKey(store.runsByProject, root) ? store.runsByProject[root] : []
    for (var i = 0; i < list.length; i++) {
      if (list[i] !== null && typeof list[i] === "object" && list[i].id === id) return true
    }
    return false
  }

  // The liveness tick: a snapshot of the usable roots whose runsByProject
  // list holds a running run, in registry order; none, nothing.
  function refreshLive() {
    var usable = store.usableRoots()
    var roots = []
    for (var i = 0; i < usable.length; i++) {
      var list = store.hasKey(store.runsByProject, usable[i].root) ? store.runsByProject[usable[i].root] : []
      for (var j = 0; j < list.length; j++) {
        if (Runs.runState(list[j]) === "running") {
          roots.push(usable[i].root)
          break
        }
      }
    }
    if (roots.length > 0) store.requestSnapshot(roots)
  }

  // Starts over: the snapshot in flight (the old store's) is stopped and the
  // pending request dropped, the coverage (appliedSeq, asOfSeq) and the live
  // state (forgetLive) are forgotten, and one list snapshot of every root is
  // launched.
  function resetCursor() {
    store.dropSnapshots()
    store.appliedSeq = {}
    store.asOfSeq = 0
    store.forgetLive()
    store.refresh()
  }

  // The live state of the store last seen is forgotten: the cursor, the
  // nudges and their debounce, the runs and every root's list of them, and
  // the alerts (the next list snapshot only arms). Selection, logs, controls
  // and dispatch stay.
  function forgetLive() {
    store.watchCursor = 0
    store.nudges = {}
    debounceTimer.stop()
    store.runs = []
    store.runsByProject = {}
    store.armedRoots = {}
  }

  // A store id seen in a hello. A non-empty string is recorded as storeId;
  // anything else is no store id and changes nothing.
  // Returns whether it names another store than the one last seen: storeId
  // was non-empty and differs. The first one seen is no change.
  function seeStore(id) {
    if (typeof id !== "string" || id === "") return false
    var changed = store.storeId !== "" && store.storeId !== id
    store.storeId = id
    return changed
  }

  // amSchema and amVersion back to unknown: no current watch has said hello.
  function forgetHello() {
    store.amSchema = 0
    store.amVersion = ""
  }

  // The watch ended, whatever the code: its hello no longer holds, so amSchema
  // and amVersion are reset. Exit 0: it was stopped (by us, or because am
  // exited). Otherwise the last envelope line it printed says why: a journal
  // the helper cannot read switches to the 5 s poll; anything else is reported
  // and the watch stays off until the next activation.
  function watchExited(proc, exitCode) {
    if (!store.isCurrentWatch(proc)) return
    watchState.watching = false
    store.forgetHello()
    if (exitCode === 0) return
    var envelope = proc.envelope
    var err = envelope ? envelope.error : null
    var type = err !== null && typeof err === "object" ? err.type : ""
    if (type === "SchemaMismatch") {
      store.watchSchemaError = Runs.errorText(envelope)
      store.amStatus = "schema"
      store.lastError = store.watchSchemaError
      store.startPoll()
    } else if (type === "CorruptJournal") {
      store.watchWarning = Runs.errorText(envelope)
      store.startPoll()
    } else {
      store.lastError = envelope ? Runs.errorText(envelope) : "The runs watch stopped (exit " + exitCode + ")."
    }
  }

  // The poll replaces the watch signal until the panel closes.
  function startPoll() {
    pollTimer.start()
  }

  function stopPoll() {
    pollTimer.stop()
    store.watchSchemaError = ""
  }

  // Another project was opened, or none. The run list, the selection, the
  // logs, the watch, the coverage, the requests (pending, stillWaiting,
  // controlRunners), the control error, the cancel dialog, the footer flash,
  // the alerts, the toasts and the notify switch belong to every registered
  // project and stay, and no snapshot is launched. Reset: the run settings
  // (loaded for the new project on runSettingsRunner) and the dispatch.
  function projectSwitched() {
    store.runSettings = {}
    // The dispatch is the old project's, even mid-start: a start already
    // launched still runs, and its reply is no longer this dispatch's.
    store.resetDispatch()
    runSettingsRunner.guard = store.project
    if (store.project !== "") runSettingsRunner.run(["get-run-settings", store.project])
  }

  onProjectChanged: store.projectSwitched()

  // The registry's usable entries, {root, name}, in registry order: an object
  // whose root is a non-empty string not starting with "-" (runs-snapshot-all.py
  // refuses any other), each root once, at its first position with its first
  // name.
  function usableRoots() {
    var list = store.projectRoots
    var n = list !== null && typeof list === "object" && typeof list.length === "number" ? list.length : 0
    var out = []
    var seen = {}
    for (var i = 0; i < n; i++) {
      var p = list[i]
      if (p === null || typeof p !== "object" || Array.isArray(p)) continue
      var root = p.root
      if (typeof root !== "string" || root === "" || root.charAt(0) === "-" || store.hasKey(seen, root)) continue
      seen[root] = true
      out.push({ root: root, name: p.name })
    }
    return out
  }

  // byProject cut to the usable roots, each run carrying its root's current
  // project (Runs.withProject); a run that already carries it stays the same
  // object.
  function taggedByProject(byProject, usable) {
    var out = {}
    for (var i = 0; i < usable.length; i++) {
      var p = usable[i]
      if (!store.hasKey(byProject, p.root)) continue
      var tag = Runs.withProject({}, p.root, p.name).project
      out[p.root] = byProject[p.root].map(function(run) {
        var cur = run !== null && typeof run === "object" ? run.project : null
        if (cur && cur.root === tag.root && cur.name === tag.name) return run
        return Runs.withProject(run, p.root, p.name)
      })
    }
    return out
  }

  // byProject's lists over the usable roots in registry order, as {runs,
  // owner}: a run id an earlier root already listed is dropped (the first root
  // wins; a run without a non-empty string id is never dropped), and owner is
  // {id: root} of every run id kept.
  function mergedRuns(byProject, usable) {
    var out = []
    var owner = {}
    for (var i = 0; i < usable.length; i++) {
      var root = usable[i].root
      var list = store.hasKey(byProject, root) ? byProject[root] : []
      for (var j = 0; j < list.length; j++) {
        var run = list[j]
        var id = run !== null && typeof run === "object" && typeof run.id === "string" ? run.id : ""
        if (id !== "") {
          if (store.hasKey(owner, id)) continue
          owner[id] = root
        }
        out.push(run)
      }
    }
    return { runs: out, owner: owner }
  }

  // The registry changed. First the roots no longer usable lose their runs,
  // their errors and their arming (armedRoots is replaced only when a root
  // went), and `runs` is merged again in the new order with the new names;
  // no alert is raised. Then every usable root is snapshotted.
  function registryChanged() {
    var usable = store.usableRoots()
    var errors = {}
    var armed = {}
    for (var i = 0; i < usable.length; i++) {
      var root = usable[i].root
      if (store.hasKey(store.projectErrors, root)) errors[root] = store.projectErrors[root]
      if (store.hasKey(store.armedRoots, root)) armed[root] = true
    }
    var byProject = store.taggedByProject(store.runsByProject, usable)
    store.runsByProject = byProject
    store.projectErrors = errors
    if (Object.keys(armed).length !== Object.keys(store.armedRoots).length) store.armedRoots = armed
    store.runs = store.mergedRuns(byProject, usable).runs
    store.refresh()
  }

  onProjectRootsChanged: store.registryChanged()

  // ---- attempt logs (5.2)

  // The run with this id in the snapshot, or null.
  function runById(id) {
    var list = store.runs
    for (var i = 0; i < list.length; i++) {
      if (list[i] && list[i].id === id) return list[i]
    }
    return null
  }

  // The run's project root when it is a non-empty string, else "".
  function runRoot(run) {
    var p = run !== null && typeof run === "object" ? run.project : null
    if (p === null || typeof p !== "object" || typeof p.root !== "string") return ""
    return p.root
  }

  // Shows (and fetches) one attempt of the selected run. Another attempt than
  // the one shown starts from an empty pane -- its predecessor's text is never
  // shown under its heading. Nothing happens without a selected run, a
  // non-empty card and phase, and an attempt that is a number 0 or above; 0 is
  // the phase's newest output, am's choice.
  function selectAttempt(cardId, phase, attempt) {
    if (store.selectedRunId === "") return
    if (typeof cardId !== "string" || cardId === "" || typeof phase !== "string" || phase === "") return
    if (typeof attempt !== "number" || !isFinite(attempt) || attempt < 0) return
    var old = store.selectedAttempt
    if (!old || old.card_id !== cardId || old.phase !== phase || old.attempt !== attempt) {
      store.logsText = ""
      store.logsTruncated = false
      store.logsFetchedMs = 0
      store.logsError = ""
    }
    store.selectedAttempt = { card_id: cardId, phase: phase, attempt: attempt }
    store.fetchLogs()
  }

  // The Refresh button: the same attempt again; the text stays until the reply.
  function refreshLogs() {
    store.fetchLogs()
  }

  // One runs-logs.py launch for the selected attempt, the selected run's
  // project root first, remembering the status it was launched for (a
  // snapshot that changes it fetches again). Nothing launches for a run not
  // in the snapshot or one with no project root.
  function fetchLogs() {
    var sel = store.selectedAttempt
    if (store.selectedRunId === "" || !sel) return
    var run = store.runById(store.selectedRunId)
    var root = store.runRoot(run)
    if (root === "") return
    store.logsStatus = Runs.attemptStatus(run, sel.card_id, sel.phase, sel.attempt)
    store.logsLoading = true
    logsRunner.run([root, store.selectedRunId, sel.card_id, sel.phase, String(sel.attempt)])
  }

  // No selection, no logs and no recorded run state; a fetch in flight is
  // stopped and its reply dropped.
  function clearLogs() {
    logsRunner.cancel()
    store.selectedAttempt = null
    store.logsText = ""
    store.logsTruncated = false
    store.logsFetchedMs = 0
    store.logsLoading = false
    store.logsError = ""
    store.logsStatus = ""
    store.logsRunState = ""
  }

  // The selected run's opening attempt: the attempt its stop report names,
  // else its default attempt. It is selected when there is one; with none the
  // selection is left alone. Either way logsRunState becomes the run's
  // Runs.runState, or "" when the run is not in the snapshot.
  function openDefaultAttempt() {
    var run = store.runById(store.selectedRunId)
    var report = Runs.stopReport(run)
    var target = report !== null && report.attempt !== null ? report.attempt : Runs.defaultAttempt(run)
    store.logsRunState = run !== null ? Runs.runState(run) : ""
    if (target) store.selectAttempt(target.card_id, target.phase, target.attempt)
  }

  // After every applied snapshot, for a selected run: when the run is in the
  // snapshot and its Runs.runState is not logsRunState, it opens on its
  // opening attempt again, over any attempt picked since; otherwise a run with
  // no attempt yet gets its opening attempt once one exists, and the selected
  // attempt is fetched again only when its status moved since its fetch was
  // launched. Nothing else fetches logs on its own.
  function logsAfterSnapshot() {
    if (store.selectedRunId === "") return
    var run = store.runById(store.selectedRunId)
    if (run !== null && Runs.runState(run) !== store.logsRunState) {
      store.openDefaultAttempt()
      return
    }
    var sel = store.selectedAttempt
    if (!sel) {
      store.openDefaultAttempt()
      return
    }
    var status = Runs.attemptStatus(run, sel.card_id, sel.phase, sel.attempt)
    if (status !== store.logsStatus) store.fetchLogs()
  }

  // Another run (or none): the pane starts over, and a selected run opens on
  // its opening attempt.
  onSelectedRunIdChanged: {
    store.clearLogs()
    if (store.selectedRunId !== "") store.openDefaultAttempt()
  }

  // One logs reply. ok:true replaces the text with its last 200 lines; any
  // failure keeps the text and only says why. Never touches amStatus, runs or
  // lastError: those belong to the snapshot. A reply for an older fetch never
  // gets here (the runner's latest-wins).
  function applyLogs(stdout, exitCode) {
    store.logsLoading = false
    var envelope = store.parseEnvelope(stdout)
    if (envelope !== null && envelope.ok === true) {
      var tail = Runs.logTail(envelope.data, 200)
      store.logsText = tail.text
      store.logsTruncated = tail.truncated
      store.logsFetchedMs = Date.now()
      store.logsError = ""
      return
    }
    if (envelope !== null && envelope.ok === false) {
      store.logsError = Runs.errorText(envelope)
      return
    }
    store.logsError = "The logs snapshot gave no usable result (exit " + exitCode + ")."
  }

  // The helper prints exactly one JSON line; anything before it (a warning) and
  // blank lines after it are ignored.
  function lastLine(text) {
    var lines = String(text || "").split("\n")
    for (var i = lines.length - 1; i >= 0; i--) {
      var line = lines[i].trim()
      if (line !== "") return line
    }
    return ""
  }

  // The reply's envelope object, or null when there is none to read.
  function parseEnvelope(text) {
    var line = store.lastLine(text)
    if (line === "") return null
    var value = null
    try { value = JSON.parse(line) } catch (e) { return null }
    return value !== null && typeof value === "object" && !Array.isArray(value) ? value : null
  }

  // The `am runs` summary without its `status` key: the helper replaced the
  // summary's status string with the `am status` object, which normalizeRun
  // must never read as the row's status ("[object Object]").
  function rowOf(entry) {
    var row = {}
    for (var key in entry) {
      if (key !== "status" && Object.prototype.hasOwnProperty.call(entry, key)) row[key] = entry[key]
    }
    return row
  }

  // A non-negative integer: an as_of_seq or a cursor.
  function isSeq(value) {
    return typeof value === "number" && Number.isInteger(value) && value >= 0
  }

  // One list snapshot reply, for the roots it was launched with. {ok: true,
  // projects} goes to applyProjects. An ok:false envelope (Usage,
  // HelperError) or output that is not one keeps the runs, runsByProject and
  // projectErrors and only reports why this one failed. Never reads a
  // store_id. Never throws.
  function applySnapshot(stdout, exitCode, launched) {
    var envelope = store.parseEnvelope(stdout)
    if (envelope !== null && envelope.ok === true) {
      store.applyProjects(Array.isArray(envelope.projects) ? envelope.projects : [], exitCode, launched)
      return
    }
    store.amStatus = "error"
    if (envelope !== null && envelope.ok === false) store.lastError = Runs.errorText(envelope)
    else store.lastError = "The runs snapshot gave no usable result (exit " + exitCode + ")."
  }

  // A list reply's entries, {root, ok, runs | error}, matched to the usable
  // roots by exact root: the first entry of a root counts, any other entry is
  // ignored. No matched entry at all is a reply with no usable result --
  // unless none of the roots it was launched for (`launched`) is usable any
  // more, when it changes nothing. Every
  // matched entry AmMissing: the runs, runsByProject, projectErrors and the
  // coverage are emptied and amStatus is "missing", and every root is disarmed.
  // Otherwise an ok entry replaces its root's runs and clears its error
  // (entries that are not objects are skipped); a failed one keeps its
  // root's runs ([] when it had none) and records Runs.errorText of its
  // error; a usable root with no entry keeps both. `runs` is merged again,
  // and asOfSeq is 0 and appliedSeq {id: 0} for every run in it. With an
  // entry ok, everything after a good snapshot follows, and while active a
  // running watch whose roots are no longer the usable "/" roots is started
  // again, the alerts of every armed root with an ok entry are raised
  // (alertsOf) and every root with an ok entry is armed. With none, amStatus
  // is "error" with the first failed entry's sentence, and armedRoots and
  // `stale` stay as they are. A failed entry, a root with no entry and a
  // closed panel never change armedRoots.
  function applyProjects(entries, exitCode, launched) {
    var usable = store.usableRoots()
    var names = {}
    for (var u = 0; u < usable.length; u++) names[usable[u].root] = usable[u].name
    var matched = []
    var seen = {}
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i]
      if (e === null || typeof e !== "object" || Array.isArray(e)) continue
      if (typeof e.root !== "string" || !store.hasKey(names, e.root) || store.hasKey(seen, e.root)) continue
      seen[e.root] = true
      matched.push(e)
    }
    if (matched.length === 0) {
      var gone = true
      var roots = Array.isArray(launched) ? launched : []
      for (var g = 0; g < roots.length; g++) {
        if (store.hasKey(names, roots[g])) gone = false
      }
      if (gone && roots.length > 0) return
      store.amStatus = "error"
      store.lastError = "The runs snapshot gave no usable result (exit " + exitCode + ")."
      return
    }
    var missing = true
    for (var m = 0; m < matched.length; m++) {
      var err = matched[m].error
      var type = err !== null && typeof err === "object" ? err.type : ""
      if (matched[m].ok === true || type !== "AmMissing") missing = false
    }
    if (missing) {
      store.runs = []
      store.runsByProject = {}
      store.projectErrors = {}
      store.appliedSeq = {}
      store.asOfSeq = 0
      store.amStatus = "missing"
      store.lastError = Runs.errorText(matched[0].error)
      // Every root is disarmed: comparing its next good entry against []
      // would alert every escalated run again.
      store.armedRoots = {}
      return
    }
    var prev = store.runsByProject
    var byProject = store.copyMap(store.runsByProject)
    var errors = store.copyMap(store.projectErrors)
    var anyOk = false
    var okRoots = {}
    var firstError = ""
    for (var k = 0; k < matched.length; k++) {
      var entry = matched[k]
      var root = entry.root
      if (entry.ok === true) {
        anyOk = true
        okRoots[root] = true
        var list = Array.isArray(entry.runs) ? entry.runs : []
        var out = []
        for (var r = 0; r < list.length; r++) {
          var item = list[r]
          if (item === null || typeof item !== "object" || Array.isArray(item)) continue
          out.push(Runs.withProject(Runs.normalizeRun({ row: store.rowOf(item), status: item.status }), root, names[root]))
        }
        byProject[root] = out
        delete errors[root]
      } else {
        if (!store.hasKey(byProject, root)) byProject[root] = []
        errors[root] = Runs.errorText(entry.error)
        if (firstError === "") firstError = errors[root]
      }
    }
    byProject = store.taggedByProject(byProject, usable)
    var merged = store.mergedRuns(byProject, usable)
    var applied = {}
    var ids = Object.keys(merged.owner)
    for (var d = 0; d < ids.length; d++) applied[ids[d]] = 0
    // Compared before the runs are replaced; raised below only while open.
    var alerts = store.active ? store.alertsOf(prev, byProject, merged.owner, okRoots, usable) : []
    store.runsByProject = byProject
    store.projectErrors = errors
    store.asOfSeq = 0
    store.appliedSeq = applied
    store.runs = merged.runs
    if (!anyOk) {
      store.amStatus = "error"
      store.lastError = firstError
      return
    }
    store.settleAfterSnapshot()
    store.logsAfterSnapshot()
    if (pollTimer.running && store.watchSchemaError !== "") {
      // The watch's schema banner outlives the polling snapshots.
      store.amStatus = "schema"
      store.lastError = store.watchSchemaError
    } else {
      store.amStatus = "ok"
      store.lastError = ""
    }
    store.stale = false
    if (store.active) {
      staleTimer.restart()
      if (!store.watchTried) store.startWatch()
      else if (store.watching && !store.sameRoots(watchState.roots, store.watchableRoots())) {
        store.stopWatch()
        store.startWatch()
      }
      store.raiseAlerts(alerts)
      var armed = store.copyMap(store.armedRoots)
      for (var ok in okRoots) armed[ok] = true
      store.armedRoots = armed
    }
  }

  // One list reply's alerts, in registry order, then each root's order: for
  // every armed root in okRoots, Runs.newAlerts of its runs before the reply
  // (prev; [] when it had none) against the runs of byProject it owns in the
  // merged list (owner), each with `project`, the name Runs.withProject gives
  // that root. A run id is raised at most once.
  function alertsOf(prev, byProject, owner, okRoots, usable) {
    var out = []
    var raised = {}
    for (var i = 0; i < usable.length; i++) {
      var root = usable[i].root
      if (!store.hasKey(okRoots, root) || !store.hasKey(store.armedRoots, root)) continue
      var mine = byProject[root].filter(function(run) {
        return run !== null && typeof run === "object" && store.hasKey(owner, run.id) && owner[run.id] === root
      })
      var name = Runs.withProject({}, root, usable[i].name).project.name
      var found = Runs.newAlerts(store.hasKey(prev, root) ? prev[root] : [], mine)
      for (var j = 0; j < found.length; j++) {
        if (store.hasKey(raised, found[j].id)) continue
        raised[found[j].id] = true
        found[j].project = name
        out.push(found[j])
      }
    }
    return out
  }

  // ---- run controls (S2 4.1)

  // A copy of a {key: value} map, so a change is a new object.
  function copyMap(map) {
    var out = {}
    for (var key in map) {
      if (Object.prototype.hasOwnProperty.call(map, key)) out[key] = map[key]
    }
    return out
  }

  function hasKey(map, key) {
    return Object.prototype.hasOwnProperty.call(map, key)
  }

  // A new request for runId, a run in `runs`: the control error is dismissed,
  // the request is recorded with the run's state as its baseline, pending is
  // set, and its runner (repo_dir and project.root of the run, not launched
  // yet) joins controlRunners and is returned.
  function startRequest(action, runId) {
    var run = store.runById(runId)
    store.dismissControlError()
    controlState.nextToken += 1
    var requests = store.copyMap(controlState.requests)
    requests[runId] = { token: controlState.nextToken, action: action, baseline: Runs.runState(run),
                        launchedMs: Date.now(), acknowledged: false, requestedAt: "" }
    controlState.requests = requests
    var p = store.copyMap(store.pending)
    p[runId] = action
    store.pending = p
    var runner = controlC.createObject(store, { runId: runId, action: action, token: controlState.nextToken,
                                                repoDir: run.repo_dir, projectRoot: store.runRoot(run) })
    controlState.runners = controlState.runners.concat([runner])
    return runner
  }

  // Starts a pause, resume or cancel of one run in `runs`, of any project, and
  // returns whether it started: only when refusalOf(action, runId) is "".
  // The request acts on the run's repo_dir; a milestone resume reads the run
  // settings of the run's project.root. Confirming a cancel is the caller's job.
  function control(action, runId) {
    if (store.refusalOf(action, runId) !== "") return false
    var run = store.runById(runId)
    var runner = store.startRequest(action, runId)
    if (action === "resume" && run.workflow !== "task") {
      // A milestone resume reuses its project's stored verify set: read it first.
      runner.settingsStep = true
      runner.script = store.backendDir + "projects/viewer-state.py"
      runner.run(["get-run-settings", runner.projectRoot])
    } else {
      store.launchControl(runner, [])
    }
    return true
  }

  // The request's run-control.py launch on its own runner: ACTION RUN REPO,
  // REPO the repo_dir the request was made with, then `extra` (a resume's
  // verify arguments).
  function launchControl(runner, extra) {
    runner.script = store.backendDir + "runs/run-control.py"
    runner.run([runner.action, runner.runId, runner.repoDir].concat(extra))
  }

  // The request this runner was launched for, while it is still the one
  // pending for its run; null once it was settled or replaced by a newer
  // request.
  function requestOf(runner) {
    if (!store.hasKey(controlState.requests, runner.runId)) return null
    var req = controlState.requests[runner.runId]
    return req.token === runner.token ? req : null
  }

  // The request for runId is over: its pending entry, its still-waiting mark
  // and its bookkeeping go.
  function settle(runId) {
    if (store.hasKey(store.pending, runId)) {
      var p = store.copyMap(store.pending)
      delete p[runId]
      store.pending = p
    }
    if (store.hasKey(store.stillWaiting, runId)) {
      var w = store.copyMap(store.stillWaiting)
      delete w[runId]
      store.stillWaiting = w
    }
    if (store.hasKey(controlState.requests, runId)) {
      var r = store.copyMap(controlState.requests)
      delete r[runId]
      controlState.requests = r
    }
  }

  // A request ended without am taking it: the buttons come back and the
  // sentence shows under that run. `type` is am's error type when a string,
  // else "".
  function failControl(runId, sentence, type) {
    store.settle(runId)
    store.lastControlError = sentence
    store.lastControlErrorRunId = runId
    store.lastControlErrorType = typeof type === "string" ? type : ""
  }

  function dismissControlError() {
    store.lastControlError = ""
    store.lastControlErrorRunId = ""
    store.lastControlErrorType = ""
  }

  // A runner's request is over: it leaves controlRunners and is destroyed.
  function dropRunner(runner) {
    controlState.runners = controlState.runners.filter(function(r) { return r !== runner })
    runner.destroy()
  }

  // One run-control.py reply, whatever project is open. ok:true
  // means am has the request: pending stays until a snapshot settles it, and
  // the requested_at am gave it is remembered. Anything else ends it with a
  // sentence. Either way the runs are fetched again. A reply for a request that
  // is no longer the pending one changes nothing.
  function controlReplied(runner, stdout, exitCode) {
    var req = store.requestOf(runner)
    if (req === null) {
      store.dropRunner(runner)
      return
    }
    if (runner.settingsStep) {
      runner.settingsStep = false
      store.resumeWithSettings(runner, stdout, exitCode)
      return
    }
    var envelope = store.parseEnvelope(stdout)
    if (envelope !== null && envelope.ok === true) {
      var data = envelope.data
      var requestedAt = data !== null && typeof data === "object" && typeof data.requested_at === "string" ? data.requested_at : ""
      var requests = store.copyMap(controlState.requests)
      requests[runner.runId] = { token: req.token, action: req.action, baseline: req.baseline,
                                 launchedMs: req.launchedMs, acknowledged: true, requestedAt: requestedAt }
      controlState.requests = requests
    } else if (envelope !== null && envelope.ok === false) {
      var err = envelope.error
      var type = err !== null && typeof err === "object" && typeof err.type === "string" ? err.type : ""
      store.failControl(runner.runId, Runs.controlError(envelope), type)
    } else {
      store.failControl(runner.runId, "The run control gave no usable result (exit " + exitCode + ").", "")
    }
    store.dropRunner(runner)
    store.refresh()
  }

  // The run settings' reply for a milestone resume. A stored verify set (a
  // non-empty list of strings) goes to run-control as --verify pairs in its
  // order; otherwise the stored opt-out as --allow-no-verification. With
  // neither, the request is settled and the Resume dialog opens for the run;
  // with no readable reply, the request ends with a sentence. In both,
  // run-control is never launched and there is no re-snapshot.
  function resumeWithSettings(runner, stdout, exitCode) {
    var settings = store.parseEnvelope(stdout)
    if (settings === null) {
      store.failControl(runner.runId, "The run settings gave no usable result (exit " + exitCode + ").", "")
      store.dropRunner(runner)
      return
    }
    var verify = Array.isArray(settings.verify) ? settings.verify : []
    var usable = verify.length > 0
    for (var i = 0; i < verify.length; i++) {
      if (typeof verify[i] !== "string") usable = false
    }
    if (usable) {
      var extra = []
      for (var j = 0; j < verify.length; j++) extra.push("--verify", verify[j])
      store.launchControl(runner, extra)
    } else if (settings.allowNoVerification === true) {
      store.launchControl(runner, ["--allow-no-verification"])
    } else {
      var runId = runner.runId
      store.settle(runId)
      store.dropRunner(runner)
      store.resumeOpenFor(runId)
    }
  }

  // After every good snapshot: an acknowledged request is settled when its run
  // is gone, when the run's state moved since the request started, or (pause,
  // cancel) when am marks its request handled. A request still in flight is
  // never settled by a snapshot: its buttons stay off until the reply.
  function settleAfterSnapshot() {
    var ids = Object.keys(store.pending)
    for (var i = 0; i < ids.length; i++) {
      var id = ids[i]
      if (!store.hasKey(controlState.requests, id)) continue
      var req = controlState.requests[id]
      if (!req.acknowledged) continue
      var run = store.runById(id)
      if (run === null || Runs.runState(run) !== req.baseline
          || (req.action !== "resume" && store.isHandled(run, req))) store.settle(id)
    }
  }

  // The run's am request row for this request has a handled_at: the row with
  // the requested_at am's reply gave, else the last row of the same command.
  function isHandled(run, req) {
    var list = Array.isArray(run.requests) ? run.requests : []
    var match = null
    for (var i = 0; i < list.length; i++) {
      var row = list[i]
      if (req.requestedAt !== "" ? row.requested_at === req.requestedAt : row.command === req.action) match = row
    }
    return match !== null && match.handled_at !== ""
  }

  // Marks the pending requests launched 30 s or more before nowMs (the timer
  // passes Date.now()); the UI shows stillWaitingText for them.
  function checkWaiting(nowMs) {
    var out = {}
    var ids = Object.keys(store.pending)
    for (var i = 0; i < ids.length; i++) {
      var id = ids[i]
      if (store.hasKey(controlState.requests, id) && nowMs - controlState.requests[id].launchedMs >= 30000) out[id] = true
    }
    store.stillWaiting = out
  }

  // ---- cancel confirmation and the footer flash (S2 4.3)

  // "" when control(action, runId) would start a request; otherwise why not:
  // a run that is not in the snapshot, then a run with no repo_dir, then a
  // resume (not of a task run) of a run with no project root, then a request
  // already pending for it, then the reason Runs.controls gives. Changes nothing.
  function refusalOf(action, runId) {
    if (action !== "pause" && action !== "resume" && action !== "cancel") return "Unknown control"
    var run = typeof runId !== "string" || runId === "" ? null : store.runById(runId)
    if (run === null) return "This run is no longer in the snapshot"
    if (typeof run.repo_dir !== "string" || run.repo_dir === "") return "This run has no repository"
    if (action === "resume" && run.workflow !== "task" && store.runRoot(run) === "") return "This run's project is not known"
    if (store.hasKey(store.pending, runId)) return "A request for this run is pending"
    return Runs.controls(run)[action].reason
  }

  // Shows text in the footers for 3 s; a new flash replaces it and restarts
  // the clock, flash("") clears it.
  function flash(text) {
    store.flashText = String(text || "")
    if (store.flashText === "") flashTimer.stop()
    else flashTimer.restart()
  }

  // Opens the cancel confirmation for a run that can be cancelled now;
  // otherwise flashes why not and leaves any dialog as it is.
  function openCancel(runId) {
    var reason = store.refusalOf("cancel", runId)
    if (reason !== "") {
      store.flash(reason)
      return false
    }
    store.cancelText = ""
    store.cancelError = ""
    store.cancelRunId = runId
    return true
  }

  function closeCancel() {
    store.cancelRunId = ""
    store.cancelText = ""
    store.cancelError = ""
  }

  // The dialog's confirm. The typed word is checked again here (the dialog
  // gates it too), then the run is checked again: one that changed under the
  // open dialog keeps it open with the reason. A started cancel closes it.
  function confirmCancel() {
    if (store.cancelRunId === "") return false
    if (String(store.cancelText).trim().toLowerCase() !== "cancel") return false
    var reason = store.refusalOf("cancel", store.cancelRunId)
    if (reason !== "") {
      store.cancelError = reason
      return false
    }
    if (!store.control("cancel", store.cancelRunId)) {
      store.cancelError = "The run could not be cancelled"
      return false
    }
    store.closeCancel()
    return true
  }

  // ---- resume dialog

  // The Resume dialog: a milestone resume with no stored verify set asks for
  // the commands here. `resumeRunId` is the run it asks about ("" = closed),
  // `resumeVerify` the commands as typed (blanks allowed),
  // `resumeAllowNoVerification` the opt-out, and `resumeError` why the last
  // confirm was refused.
  property string resumeRunId: ""
  property var resumeVerify: []
  property bool resumeAllowNoVerification: false
  property string resumeError: ""

  // Opens the dialog for runId with empty fields, replacing any open one, and
  // returns true. Returns false and changes nothing when runId is not a
  // non-empty string, its run is not in the snapshot, or it is a task run.
  function resumeOpenFor(runId) {
    if (typeof runId !== "string" || runId === "") return false
    var run = store.runById(runId)
    if (run === null || run.workflow === "task") return false
    store.resumeVerify = []
    store.resumeAllowNoVerification = false
    store.resumeError = ""
    store.resumeRunId = runId
    return true
  }

  function resumeClose() {
    store.resumeRunId = ""
    store.resumeVerify = []
    store.resumeAllowNoVerification = false
    store.resumeError = ""
  }

  // The dialog's confirm. Refused, with resumeError and the dialog left open,
  // when the form has no non-blank command and no opt-out, or when the run
  // cannot be resumed now (refusalOf). Otherwise the resume starts as
  // control() starts one and launches run-control at once: the non-blank
  // commands as --verify pairs in order, else --allow-no-verification. The
  // set is saved for the run's project without waiting for the reply, the
  // dialog closes, and true is returned.
  function resumeConfirm() {
    if (store.resumeRunId === "") return false
    var form = { verify: store.resumeVerify, allowNoVerification: store.resumeAllowNoVerification }
    var missing = Runs.validateDispatch(form).errors.filter(function(e) { return e.field === "verify" })
    if (missing.length > 0) {
      store.resumeError = missing[0].message
      return false
    }
    var runId = store.resumeRunId
    var reason = store.refusalOf("resume", runId)
    if (reason !== "") {
      store.resumeError = reason
      return false
    }
    var commands = store.dispatchCommands(form)
    var extra = []
    for (var i = 0; i < commands.length; i++) extra.push("--verify", commands[i])
    if (commands.length === 0) extra = ["--allow-no-verification"]
    var runner = store.startRequest("resume", runId)
    store.launchControl(runner, extra)
    resumeSaveRunner.run(["set-run-settings", runner.projectRoot,
                          JSON.stringify({ verify: commands, allowNoVerification: store.resumeAllowNoVerification === true })])
    store.resumeClose()
    return true
  }

  // set-run-settings: {"ok": true} changes nothing; anything else flashes.
  // Never touches the request, the control error or the dialog.
  function resumeSaveReplied(stdout, exitCode) {
    var reply = store.parseEnvelope(stdout)
    if (reply !== null && reply.ok === true) return
    store.flash("The verify commands could not be saved")
  }

  // set-run-settings for a confirmed resume; latest wins. No guard: the save
  // is for the run's project, whatever project is open.
  HelperRunner {
    id: resumeSaveRunner
    script: store.backendDir + "projects/viewer-state.py"
    onFinished: function(stdout, exitCode) { store.resumeSaveReplied(stdout, exitCode) }
  }
  readonly property alias resumeSaveRunner: resumeSaveRunner

  // ---- alerts (S2 4.4)

  // One toast per alert, newest last: a run's older toast goes first, then the
  // oldest beyond three. With the setting on, each alert also notifies.
  // Called from applySnapshot only while active.
  function raiseAlerts(alerts) {
    var list = Array.isArray(alerts) ? alerts : []
    for (var i = 0; i < list.length; i++) {
      var a = list[i]
      toastState.nextKey += 1
      var next = store.toasts.filter(function(t) { return t.id !== a.id })
      next.push({ key: toastState.nextKey, id: a.id, title: a.title, state: a.state, reason: a.reason,
                  project: typeof a.project === "string" ? a.project : "", expiresMs: Date.now() + store.toastMs })
      while (next.length > 3) next.shift()
      store.toasts = next
      if (store.notifyOnEscalation) store.notify(a)
    }
  }

  // Drops every toast whose time is up at nowMs (the timer passes Date.now()).
  function expireToasts(nowMs) {
    var next = store.toasts.filter(function(t) { return t.expiresMs > nowMs })
    if (next.length !== store.toasts.length) store.toasts = next
  }

  // The toast with this key goes; an unknown key changes nothing.
  function dismissToast(key) {
    var next = store.toasts.filter(function(t) { return t.key !== key })
    if (next.length !== store.toasts.length) store.toasts = next
  }

  function dismissAllToasts() {
    if (store.toasts.length > 0) store.toasts = []
  }

  // One notify.py launch for an alert, on a runner of its own so two never
  // stop each other. The reply is not read: a failed or skipped notification
  // changes nothing here.
  function notify(alert) {
    var runner = notifyC.createObject(store)
    notifyState.runners = notifyState.runners.concat([runner])
    runner.run([String(alert.title), String(alert.reason)])
  }

  function dropNotifyRunner(runner) {
    notifyState.runners = notifyState.runners.filter(function(r) { return r !== runner })
    runner.destroy()
  }

  // The switch changed: shown at once, written to the global settings in the
  // background. Always works, with or without a project, and returns true.
  function setNotifyOnEscalation(on) {
    var value = !!on
    store.notifyOnEscalation = value
    store.notifyTouched = true
    settingsSaveRunner.sent = value
    settingsSaveRunner.run(["set-global-settings", JSON.stringify({ notifyOnEscalation: value })])
    return true
  }

  // get-global-settings: only a real true turns the switch on; an unreadable
  // reply leaves it off. Too late once the user changed the switch in this
  // opening.
  function applyGlobalSettings(stdout, exitCode) {
    if (store.notifyTouched) return
    var settings = store.parseEnvelope(stdout)
    var on = settings !== null && settings.notifyOnEscalation === true
    store.notifyOnEscalation = on
    store.notifySaved = on
  }

  // get-run-settings: one bare object, kept whole as runSettings ({} when
  // unreadable) on every reply. Never touches the notify switch.
  function applyRunSettings(stdout, exitCode) {
    var settings = store.parseEnvelope(stdout)
    store.runSettings = settings !== null ? settings : {}
  }

  // set-global-settings: {"ok": true} means `sent` is stored; anything else puts
  // the switch back to what is stored and says so.
  function notifySaveReplied(stdout, exitCode, sent) {
    var reply = store.parseEnvelope(stdout)
    if (reply !== null && reply.ok === true) {
      store.notifySaved = sent
      return
    }
    store.notifyOnEscalation = store.notifySaved
    store.flash("Notify on escalation could not be saved")
  }

  // ---- dispatch (S3 3.1)

  // No refusal, failure or suggestion to show.
  function clearDispatchError() {
    store.dispatchError = ""
    store.dispatchErrorType = ""
    store.dispatchErrors = []
    store.dispatchLog = ""
    store.dispatchLogTail = ""
    store.dispatchExitCode = null
    store.dispatchSuggest = null
  }

  // Every dispatch field back to its "none" value; runSettings stays. The
  // pending check, the preview and the defaults lookup are dropped; a start
  // already launched runs on, but its reply is no longer this dispatch's.
  function resetDispatch() {
    dispatchDebounceTimer.stop()
    dispatchPreviewRunner.cancel()
    dispatchDefaultsRunner.cancel()
    dispatchBook.startRunner = null
    dispatchBook.baseTouched = false
    dispatchBook.defaultsPending = false
    dispatchBook.cardMap = null
    dispatchBook.milestone = null
    store.dispatchState = "idle"
    store.dispatchTarget = null
    store.dispatchTargetLabel = ""
    store.dispatchForm = null
    store.dispatchPreview = null
    store.clearDispatchError()
    store.dispatchRunId = ""
    store.dispatchMessage = ""
  }

  // Opens the dispatch for a brd card (as Board.indexTree() leaves it) or
  // "board", with its {id: card} map, and returns whether it may be started.
  // Refused (false, nothing changes) without a project or while a start is in
  // flight. Every opening sets dispatchTargetLabel and records cardMap and
  // cardMap's entry for the target's milestone (Runs.dispatchMilestone), or
  // null. A target dispatchPlan does not offer is `refused` at once; any
  // other starts from dispatchDefaults with this project's runSettings and
  // the Runs snapshot, and looks up the default branch before anything is
  // checked.
  function openDispatch(card, cardMap) {
    if (store.project === "" || store.dispatchState === "starting") return false
    store.resetDispatch()
    var plan = Runs.dispatchPlan(card, cardMap)
    var milestone = Runs.dispatchMilestone(card, cardMap)
    var isMap = cardMap !== null && typeof cardMap === "object"
    dispatchBook.cardMap = cardMap
    dispatchBook.milestone = milestone !== null && isMap && store.hasKey(cardMap, milestone.id) ? cardMap[milestone.id] : null
    store.dispatchTarget = plan
    store.dispatchTargetLabel = Runs.dispatchLabel(card, cardMap)
    if (!plan.offered) {
      store.dispatchState = "refused"
      store.dispatchError = plan.reason
      store.dispatchErrorType = "Target"
      return false
    }
    var d = Runs.dispatchDefaults({ defaultBranch: "", settings: store.runSettings }, card, cardMap, store.runs)
    store.dispatchForm = { base: d.base, prefix: d.prefix, verify: d.verify, parallelism: d.parallelism,
                           allowNoVerification: d.allowNoVerification }
    store.dispatchState = "previewing"
    dispatchBook.defaultsPending = true
    dispatchDefaultsRunner.run(["--defaults", store.project])
    return true
  }

  // Back to idle. Refused while a start is in flight: its outcome must land in
  // a dialog that still shows what was started.
  function closeDispatch() {
    if (store.dispatchState === "starting") return false
    store.resetDispatch()
    return true
  }

  // The milestone a StoryBlockedError refusal offers: the recorded milestone
  // card as Runs.dispatchMilestone's {id, title} when the target is a story
  // and its milestone is known, else null.
  function blockedSuggest() {
    if (store.dispatchTarget === null || store.dispatchTarget.level !== "story" || dispatchBook.milestone === null) return null
    return Runs.dispatchMilestone(dispatchBook.milestone, dispatchBook.cardMap)
  }

  // From a blocked story's refusal (`refused` with a dispatchSuggest), opens
  // the dispatch afresh on the milestone card and cardMap recorded at the
  // story's opening and returns openDispatch's result. Refused (false,
  // nothing changes) in any other state or refusal.
  function retargetToMilestone() {
    if (store.dispatchState !== "refused" || store.dispatchSuggest === null) return false
    return store.openDispatch(dispatchBook.milestone, dispatchBook.cardMap)
  }

  // A copy of the form with one field set as given; verify is copied as a
  // fresh array when it is one. The store converts nothing else.
  function withField(form, name, value) {
    var next = store.copyMap(form)
    next[name] = name === "verify" && Array.isArray(value) ? value.slice() : value
    return next
  }

  // The helpers' target words: milestone ID, card ID or board.
  function dispatchTargetArgs() {
    var plan = store.dispatchTarget
    return plan.command === "board" ? ["board"] : [plan.command, plan.flags[1]]
  }

  // The form's verify commands that are non-blank strings, verbatim, in order.
  function dispatchCommands(form) {
    var list = Array.isArray(form.verify) ? form.verify : []
    return list.filter(function(c) { return typeof c === "string" && c.trim() !== "" })
  }

  // The options the preview and the start share. A blank base is left out, so
  // am uses its own default; each verify command is one argument.
  function dispatchOptionArgs() {
    var form = store.dispatchForm
    var args = []
    var base = typeof form.base === "string" ? form.base.trim() : ""
    if (base !== "") args.push("--base-branch", base)
    args.push("--branch-prefix", form.prefix.trim(), "--max-concurrent", String(form.parallelism))
    var commands = store.dispatchCommands(form)
    for (var i = 0; i < commands.length; i++) args.push("--verify", commands[i])
    if (form.allowNoVerification === true) args.push("--allow-no-verification")
    return args
  }

  // The --defaults reply: a non-blank default branch becomes base unless the
  // user set base since the opening; anything else leaves base as it is.
  // Then the form is checked at once.
  function dispatchDefaultsReplied(stdout) {
    if (!dispatchBook.defaultsPending || store.dispatchState !== "previewing") return
    dispatchBook.defaultsPending = false
    var envelope = store.parseEnvelope(stdout)
    var data = envelope !== null && envelope.ok === true ? envelope.data : null
    var branch = data !== null && typeof data === "object" && typeof data.default_branch === "string"
        ? data.default_branch.trim() : ""
    if (branch !== "" && !dispatchBook.baseTouched) store.dispatchForm = store.withField(store.dispatchForm, "base", branch)
    store.checkDispatch()
  }

  // The form is checked: an invalid one is refused and launches nothing, a
  // subtask is ready (am has no dry run for one card), a milestone, a story
  // or the board is previewed. Waits for the defaults lookup, whose reply checks.
  function checkDispatch() {
    if (dispatchBook.defaultsPending || store.dispatchState !== "previewing") return
    dispatchDebounceTimer.stop()
    var result = Runs.validateDispatch(store.dispatchForm)
    if (!result.ok) {
      store.dispatchState = "refused"
      store.dispatchErrors = result.errors
      store.dispatchError = result.errors[0].message
      store.dispatchErrorType = "Form"
      return
    }
    if (store.dispatchTarget.level === "subtask") {
      store.dispatchState = "ready"
      return
    }
    dispatchPreviewRunner.run([store.project].concat(store.dispatchTargetArgs(), store.dispatchOptionArgs()))
  }

  // The newest preview's reply for this project and these values (a form
  // change cancels the runner). ok: ready with Runs.previewSummary for the
  // target's level, except a story with nothing left, refused as `Nothing
  // left to run` (Empty); am's refusal: its message verbatim, and for a
  // StoryBlockedError the blockedSuggest() milestone; anything else cannot
  // be read.
  function dispatchPreviewReplied(stdout) {
    if (store.dispatchState !== "previewing") return
    var envelope = store.parseEnvelope(stdout)
    if (envelope !== null && envelope.ok === true) {
      var level = store.dispatchTarget.level
      var preview = Runs.previewSummary(envelope.data, level)
      if (level === "story" && preview.summary === "Nothing left to run") {
        store.dispatchState = "refused"
        store.dispatchError = preview.summary
        store.dispatchErrorType = "Empty"
        return
      }
      store.dispatchPreview = preview
      store.dispatchState = "ready"
      return
    }
    var err = envelope !== null && envelope.ok === false ? envelope.error : null
    var message = err !== null && typeof err === "object" && typeof err.message === "string" ? err.message : ""
    store.dispatchState = "refused"
    if (message.trim() !== "") {
      store.dispatchError = message
      store.dispatchErrorType = typeof err.type === "string" ? err.type : ""
      if (store.dispatchErrorType === "StoryBlockedError") store.dispatchSuggest = store.blockedSuggest()
    } else {
      store.dispatchError = "The preview could not be read"
      store.dispatchErrorType = ""
    }
  }

  // One form field changed (name one of base, prefix, verify, parallelism,
  // allowNoVerification) while the form may be edited: back to previewing,
  // the preview, any refusal or failure and any preview in flight dropped,
  // and the 400 ms check restarted, so a burst of changes costs one check.
  // Refused (false, nothing changes) for another name, without a form, and
  // while idle, starting or started.
  function setDispatchField(name, value) {
    if (["base", "prefix", "verify", "parallelism", "allowNoVerification"].indexOf(name) < 0) return false
    var state = store.dispatchState
    if (state !== "previewing" && state !== "ready" && state !== "refused" && state !== "failed") return false
    if (store.dispatchForm === null) return false
    store.dispatchForm = store.withField(store.dispatchForm, name, value)
    if (name === "base") dispatchBook.baseTouched = true
    store.dispatchState = "previewing"
    store.dispatchPreview = null
    store.clearDispatchError()
    dispatchPreviewRunner.cancel()
    dispatchDebounceTimer.restart()
    return true
  }

  // A fresh {milestone id: prefix} map: stored's own entries when stored is
  // an object that is not an array, then entry's, which override them, as
  // set-run-settings merges prefixByMilestone.
  function mergedPrefixes(stored, entry) {
    var merged = stored !== null && typeof stored === "object" && !Array.isArray(stored) ? store.copyMap(stored) : {}
    for (var id in entry) merged[id] = entry[id]
    return merged
  }

  // Start: only from ready. start-run.py runs on a HelperRunner of its own
  // (guard "", madeFor this project), which no preview, project switch or
  // other Start stops. The settings a successful start saves are fixed now,
  // from this project's runSettings: the non-blank verify commands sent, the
  // opt-out, the prefix sent followed by the stored history without it (at
  // most 20), the parallelism and, for a story or milestone whose milestone
  // card is known, prefixByMilestone {<milestone id>: prefix sent}.
  function dispatchStart() {
    if (store.dispatchState !== "ready") return false
    var form = store.dispatchForm
    var prefix = form.prefix.trim()
    var history = [prefix]
    var stored = Array.isArray(store.runSettings.prefixHistory) ? store.runSettings.prefixHistory : []
    for (var i = 0; i < stored.length && history.length < 20; i++) {
      var p = stored[i]
      if (typeof p === "string" && p.trim() !== "" && p !== prefix) history.push(p)
    }
    var saved = { verify: store.dispatchCommands(form), allowNoVerification: form.allowNoVerification === true,
                  prefixHistory: history, parallelism: form.parallelism }
    var level = store.dispatchTarget.level
    if ((level === "story" || level === "milestone") && dispatchBook.milestone !== null) {
      var keyed = {}
      keyed[dispatchBook.milestone.id] = prefix
      saved.prefixByMilestone = keyed
    }
    var runner = dispatchStartC.createObject(store, { madeFor: store.project, savedJson: JSON.stringify(saved) })
    dispatchBook.runners = dispatchBook.runners.concat([runner])
    dispatchBook.startRunner = runner
    store.dispatchState = "starting"
    runner.run([store.project].concat(store.dispatchTargetArgs(), store.dispatchOptionArgs()))
    return true
  }

  // A start runner's reply is this dispatch's: it was made in the current
  // project and is the runner that put the store into `starting` (an idle
  // reset, and so a project switch, forgets it).
  function isHereStart(runner) {
    return runner.madeFor === store.project && dispatchBook.startRunner === runner
  }

  // start-run.py's reply. When it is this dispatch's: ok gives `started`,
  // the run id and message, the saved values in runSettings (prefixByMilestone
  // merged per milestone id), a re-snapshot and dispatchStarted(id or null);
  // a StoryBlockedError gives `refused` with am's message, no log fields and
  // the blockedSuggest() milestone; anything else gives `failed` with what
  // the helper said. After any successful start, wherever it was made, the
  // same runner writes the saved values for the project it was made in.
  function dispatchStartReplied(runner, stdout) {
    if (runner.saving) {
      store.dispatchSaveReplied(runner, stdout)
      return
    }
    var here = store.isHereStart(runner)
    var envelope = store.parseEnvelope(stdout)
    if (envelope !== null && envelope.ok === true) {
      if (here) {
        store.dispatchRunId = typeof envelope.run_id === "string" ? envelope.run_id : ""
        store.dispatchMessage = typeof envelope.message === "string" ? envelope.message : ""
        var settings = store.copyMap(store.runSettings)
        // Parsed from the JSON that is written: a var property hands back a
        // list Runs.dispatchDefaults does not take for an array.
        var saved = JSON.parse(runner.savedJson)
        for (var key in saved) {
          settings[key] = key === "prefixByMilestone" ? store.mergedPrefixes(settings.prefixByMilestone, saved[key]) : saved[key]
        }
        store.runSettings = settings
        store.dispatchState = "started"
        store.refresh()
        store.dispatchStarted(store.dispatchRunId !== "" ? store.dispatchRunId : null)
      }
      runner.saving = true
      runner.script = store.backendDir + "projects/viewer-state.py"
      runner.run(["set-run-settings", runner.madeFor, runner.savedJson])
      return
    }
    if (here) {
      var failure = envelope !== null && envelope.ok === false ? envelope : {}
      var err = failure.error
      var isErr = err !== null && err !== undefined && typeof err === "object"
      var message = isErr && typeof err.message === "string" ? err.message : ""
      var type = isErr && typeof err.type === "string" ? err.type : ""
      var blocked = type === "StoryBlockedError"
      store.dispatchState = blocked ? "refused" : "failed"
      store.dispatchError = message.trim() !== "" ? message : "The launch could not be read"
      store.dispatchErrorType = type
      store.dispatchLog = !blocked && typeof failure.log === "string" ? failure.log : ""
      store.dispatchLogTail = !blocked && typeof failure.log_tail === "string" ? failure.log_tail : ""
      store.dispatchExitCode = !blocked && typeof failure.exit_code === "number" ? failure.exit_code : null
      store.dispatchSuggest = blocked ? store.blockedSuggest() : null
    }
    store.dropStartRunner(runner)
  }

  // set-run-settings after a start: a failure is said only while the
  // dispatch is still this one. The runner then goes.
  function dispatchSaveReplied(runner, stdout) {
    var reply = store.parseEnvelope(stdout)
    if (store.isHereStart(runner) && !(reply !== null && reply.ok === true)) store.flash("Dispatch settings could not be saved")
    store.dropStartRunner(runner)
  }

  // A start runner's work is over: it leaves dispatchStartRunners and is destroyed.
  function dropStartRunner(runner) {
    dispatchBook.runners = dispatchBook.runners.filter(function(r) { return r !== runner })
    if (dispatchBook.startRunner === runner) dispatchBook.startRunner = null
    runner.destroy()
  }

  // The one list snapshot in flight (requestSnapshot). No guard: its reply is
  // matched to the registry by root, whatever project is open. Only
  // refresh() with no usable root and resetCursor() stop it.
  HelperRunner {
    id: snapshotRunner
    script: store.backendDir + "runs/runs-snapshot-all.py"
    onFinished: function(stdout, exitCode) { store.snapshotEnded(stdout, exitCode) }
  }

  // The attempt-logs helper. No guard: a reply is applied whatever project is
  // open. A newer fetch (another attempt, a Refresh) wins over an older one.
  // Whenever the runner goes idle, no fetch is loading.
  HelperRunner {
    id: logsRunner
    script: store.backendDir + "runs/runs-logs.py"
    onBusyChanged: if (!logsRunner.busy) store.logsLoading = false
    onFinished: function(stdout, exitCode) { store.applyLogs(stdout, exitCode) }
  }

  // get-global-settings, once per opening (startLive); latest wins. No guard:
  // the switch is viewer-wide, and a reply that lands after the panel closed
  // is still applied.
  HelperRunner {
    id: settingsLoadRunner
    script: store.backendDir + "projects/viewer-state.py"
    onFinished: function(stdout, exitCode) { store.applyGlobalSettings(stdout, exitCode) }
  }

  // get-run-settings on a project switch, for runSettings only. Its guard is
  // set by projectSwitched() itself rather than bound to `project`:
  // projectSwitched() runs from onProjectChanged, before a binding here is
  // sure to have followed the project, and this launch must carry the NEW
  // project.
  HelperRunner {
    id: runSettingsRunner
    script: store.backendDir + "projects/viewer-state.py"
    onFinished: function(stdout, exitCode) { store.applyRunSettings(stdout, exitCode) }
  }

  // set-global-settings on a change of the switch; latest wins. No guard: a
  // project switch never drops its reply. `sent` is the value the latest
  // launch writes.
  HelperRunner {
    id: settingsSaveRunner
    property bool sent: false
    script: store.backendDir + "projects/viewer-state.py"
    onFinished: function(stdout, exitCode) { store.notifySaveReplied(stdout, exitCode, settingsSaveRunner.sent) }
  }

  // dispatch-preview.py --defaults, once per opening. Guarded by the project:
  // a reply for a project the user has left is dropped.
  HelperRunner {
    id: dispatchDefaultsRunner
    script: store.backendDir + "runs/dispatch-preview.py"
    guard: store.project
    onFinished: function(stdout, exitCode) { store.dispatchDefaultsReplied(stdout) }
  }

  // The dispatch preview; latest wins, and every form change cancels it.
  HelperRunner {
    id: dispatchPreviewRunner
    script: store.backendDir + "runs/dispatch-preview.py"
    guard: store.project
    onFinished: function(stdout, exitCode) { store.dispatchPreviewReplied(stdout) }
  }

  // A burst of changed lines is taken in one go (triggerNudges).
  Timer {
    id: debounceTimer
    objectName: "debounceTimer"
    interval: 250
    repeat: false
    onTriggered: store.triggerNudges()
  }

  // Only while the panel is open and a run is running: no timer while idle.
  // Each tick snapshots the roots with a running run (refreshLive).
  Timer {
    id: livenessTimer
    objectName: "livenessTimer"
    interval: 10000
    repeat: true
    running: store.active && store.hasRunningRun
    onTriggered: store.refreshLive()
  }

  // Fires 30 s after the last good snapshot (or the activation) while open.
  Timer {
    id: staleTimer
    objectName: "staleTimer"
    interval: 30000
    repeat: false
    onTriggered: store.stale = true
  }

  // Replaces the watch when it cannot read am's journal (schema or corrupt).
  Timer {
    id: pollTimer
    objectName: "pollTimer"
    interval: 5000
    repeat: true
    onTriggered: store.refresh()
  }

  // Only while the panel is open and a control request is pending: closing the
  // panel keeps `pending` but leaves no timer running.
  Timer {
    id: pendingTimer
    objectName: "pendingTimer"
    interval: 1000
    repeat: true
    running: store.active && Object.keys(store.pending).length > 0
    onTriggered: store.checkWaiting(Date.now())
  }

  // Clears the footer flash 3 s after the last flash().
  Timer {
    id: flashTimer
    objectName: "flashTimer"
    interval: 3000
    repeat: false
    onTriggered: store.flashText = ""
  }

  // Only while the panel is open and a toast shows: no timer while idle.
  Timer {
    id: toastTimer
    objectName: "toastTimer"
    interval: 250
    repeat: true
    running: store.active && store.toasts.length > 0
    onTriggered: store.expireToasts(Date.now())
  }

  // only while a change waits to be checked.
  Timer {
    id: dispatchDebounceTimer
    objectName: "dispatchDebounceTimer"
    interval: 400
    repeat: false
    onTriggered: store.checkDispatch()
  }

  // What the watch Process aliases read; kept apart so consumers cannot write it.
  // `roots` are the roots the current watch was launched with.
  QtObject {
    id: watchState
    property var proc: null
    property bool watching: false
    property var roots: []
  }

  // The list snapshots' own state; kept apart so consumers cannot write it.
  // `roots` are the roots of the snapshot in flight ([] when idle);
  // `pending` the one pending request: null, "all" or [root, ...].
  QtObject {
    id: snapshotState
    property var roots: []
    property var pending: null
  }

  // The control requests' own state; kept apart so consumers cannot write it.
  // `requests` is {runId: {token, action, baseline, launchedMs, acknowledged,
  // requestedAt}}: the run's state when the request started, when it started,
  // whether am acknowledged it, and the requested_at am gave it.
  QtObject {
    id: controlState
    property var runners: []
    property var requests: ({})
    property int nextToken: 0
  }

  // The toast keys only grow, so a stale Dismiss never removes a newer toast.
  QtObject {
    id: toastState
    property int nextKey: 0
  }

  // The notify.py runners in flight; kept apart so consumers cannot write it.
  QtObject {
    id: notifyState
    property var runners: []
  }

  // The dispatch's own bookkeeping; kept apart so consumers cannot write it.
  // `startRunner` is the runner that put the store into `starting`, forgotten
  // by an idle reset (and so by a project switch); `baseTouched` says the user
  // set base since the opening; `defaultsPending` that the --defaults lookup
  // has not replied yet; `cardMap` and `milestone` are the opening's card map
  // and its entry for the target's milestone card (null when unknown).
  QtObject {
    id: dispatchBook
    property var runners: []
    property var startRunner: null
    property bool baseTouched: false
    property bool defaultsPending: false
    property var cardMap: null
    property var milestone: null
  }

  // One HelperRunner per control request, so requests for different runs never
  // stop each other. No guard: a reply is applied whatever project is open.
  // A milestone resume uses its runner twice: viewer-state.py, then
  // run-control.py.
  Component {
    id: controlC

    HelperRunner {
      id: cr
      property string runId: ""
      property string action: ""
      property int token: 0
      property string repoDir: ""         // the run's repo_dir when the request was made
      property string projectRoot: ""     // the run's project.root then; "" when it had none
      property bool settingsStep: false   // reading the run settings; run-control comes next
      onFinished: function(stdout, exitCode) { store.controlReplied(cr, stdout, exitCode) }
    }
  }

  // One HelperRunner per notification. Guard "": a project switch does not
  // stop a notification already launched. It goes when its process exits.
  Component {
    id: notifyC

    HelperRunner {
      id: nr
      script: store.backendDir + "runs/notify.py"
      guard: ""
      onFinished: store.dropNotifyRunner(nr)
    }
  }

  // One HelperRunner per Start. Guard "": start-run.py may take ~20 s, and
  // neither a preview, a project switch nor a Start in another project may
  // stop it. After a successful start the same runner writes the settings
  // for `madeFor`; it goes when that write replies, or at once after a
  // failed start.
  Component {
    id: dispatchStartC

    HelperRunner {
      id: sr
      property string madeFor: ""     // the project the start was made in
      property string savedJson: ""   // `saved` as set-run-settings takes it
      property bool saving: false     // the settings write is in flight
      script: store.backendDir + "runs/start-run.py"
      guard: ""
      onFinished: function(stdout, exitCode) { store.dispatchStartReplied(sr, stdout) }
    }
  }

  // One Process per watch launch, so each carries what it was launched with.
  Component {
    id: watchC

    Process {
      id: wp
      objectName: "watchProc"
      property int launchSeq: 0
      property var envelope: null       // the last {"ok": false, ...} line it printed
      stdout: SplitParser { onRead: function(data) { store.watchLine(wp, data) } }
      stderr: StdioCollector { waitForEnd: true }
      onExited: function(exitCode) {
        store.watchExited(wp, exitCode)
        wp.destroy()
      }
    }
  }
}
