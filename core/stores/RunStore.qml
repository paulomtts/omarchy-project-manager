import QtQml
import Quickshell
import Quickshell.Io
import "../domain/results.js" as Results
import "../domain/runs.js" as Runs
import "../domain/runEvents.js" as RunEvents

// The am run monitor's data. One list snapshot covers every registered
// project: runs-snapshot-all.py with each usable root of `projectRoots`, in
// registry order. `runsByProject` holds each root's runs, normalized by the
// run domain model and tagged with their project; `projectErrors` the roots
// whose latest entry failed; `runs` every root's runs merged in registry
// order, a run id listed once, under the first root that lists it. A project
// switch leaves the run list alone: `project`, the open project's root, is an
// input App hands on to the other run stores; the attempt logs act on each
// run's own repo_dir. Plus the selected run, the attempt or step the Run
// detail pane shows and its `am logs` snapshot (runs-logs.py; a step is
// fetched with attempt "0"), and whether `am` could be asked at all. One list snapshot is in flight at a time, plus at most one
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
// status -- never on a timer. The selected run's events (runs-events.py RUN
// --tail 200) are fetched on a selection and on refreshEvents(), and, while
// `active`, the ones after eventsCursor (RUN --since eventsCursor) on each
// runsNudged naming the selected run -- never on a timer, and a project
// switch leaves them alone.
// Each applied list snapshot reply is announced per project
// (snapshotReplied).
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

  // The Run detail pane (5.2): which attempt or step of the selected run it
  // shows and its last `am logs` snapshot. Never a live tail.
  property var selectedAttempt: null  // { card_id, phase, attempt }, a step { card_id, phase, attempt: 0, step: true }, or null
  property string logsText: ""        // Runs.logTail of the last good reply
  property bool logsTruncated: false  // lines were cut from it
  property real logsFetchedMs: 0      // Date.now() when that reply landed; 0 before any
  property bool logsLoading: false    // a fetch is in flight
  property string logsError: ""       // why the last fetch failed; "" after a good one
  property string logsStatus: ""      // the attempt's status when its fetch was launched
  property string logsNote: ""        // a neutral sentence about the selection's output, not an error; "" when none
  property string logsRunState: ""    // the run's Runs.runState when its opening attempt was chosen; "" when not in the snapshot

  // The selected run's event timeline (3.1). `titles` is the open project's
  // card id -> title map, handed in by App. `events` is RunEvents.eventRow
  // rows, ascending seq, at most 500, replaced, never changed in place.
  // A selection empties them and fetches the run's last 200 events; leaving
  // Run detail empties them and fetches nothing. While active, a runsNudged
  // naming the selected run fetches the events after eventsCursor.
  property var titles: ({})
  property var events: []
  property int eventsDropped: 0       // the selected run's events not held
  property int eventsCursor: 0        // the highest seq seen for the selected run
  property string eventsStatus: "idle" // idle | loading | ok | error
  property string eventsError: ""     // why the last fetch failed; "" after a good one and after a reset
  property string eventsFilter: "All" // All | Phases | Failures, read by RunEvents.filterRows; the store never sets it
  // Run detail's bottom area: output | events. Every selectedRunId change
  // sets it to output; only setDetailTab and toggleDetailTab change it otherwise.
  property string detailTab: "output"

  // A debounce window's nudged run ids, each once, in first-nudge order,
  // known to the store or not. Never for a snapshot the store started itself.
  // (`runs` already owns the runsChanged name.)
  signal runsNudged(var ids)
  // One project's list snapshot reply, once its state is applied: per usable
  // root with a matched entry, in registry order, whether or not `active`.
  // `outcome` is "ok", "failed" or "missing" (AmMissing, and a start-over);
  // `previousRuns` are the root's runs before the reply ([] when it had none);
  // `runs` are, for "ok", the root's runs that the merged `runs` lists under
  // it, else [].
  signal snapshotReplied(var root, var outcome, var previousRuns, var runs)

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
  readonly property alias eventsRunner: eventsRunner

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

  // The panel opened: fetch now; the first good snapshot starts the watch,
  // and the stale clock counts from now.
  function startLive() {
    store.watchTried = false
    store.restartStale()
    store.refresh()
  }

  // The panel closed: no process and no timer is left running. The
  // pending snapshot request is dropped; a snapshot in flight runs to its end
  // and is applied. The queued events follow-up is dropped; an events fetch
  // in flight runs to its end and is applied. The project filter is back to
  // All projects, with no projectFilterToggled. The runs, the selection, the
  // events, the chip and amStatus stay for the next opening.
  function stopLive() {
    store.projectFilter = ""
    snapshotState.pending = null
    eventsState.followUp = false
    store.stopWatch()
    debounceTimer.stop()
    store.nudges = {}
    store.stopPoll()
    staleTimer.stop()
    store.stale = false
    store.watchWarning = ""
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
      var list = Runs.hasKey(store.runsByProject, usable[i].root) ? store.runsByProject[usable[i].root] : []
      for (var j = 0; j < list.length; j++) {
        var run = list[j]
        var id = run !== null && typeof run === "object" && typeof run.id === "string" ? run.id : ""
        if (id === "" || id.charAt(0) === "-" || id.charAt(0) === "/" || Runs.hasKey(seen, id)) continue
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
    } else if (Runs.hasKey(value, "cursor")) {
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
      if (next === null) next = Runs.copyMap(store.nudges)
      if (!Runs.hasKey(next, e.run) || next[e.run] < e.seq) next[e.run] = e.seq
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
    var list = Runs.hasKey(store.runsByProject, root) ? store.runsByProject[root] : []
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
      var list = Runs.hasKey(store.runsByProject, usable[i].root) ? store.runsByProject[usable[i].root] : []
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
  // nudges and their debounce, the runs and every root's list of them. Then
  // snapshotReplied(root, "missing", previousRuns, []) for every usable root,
  // in registry order. Selection, logs, controls and dispatch stay.
  function forgetLive() {
    var prev = store.runsByProject
    store.watchCursor = 0
    store.nudges = {}
    debounceTimer.stop()
    store.runs = []
    store.runsByProject = {}
    var usable = store.usableRoots()
    var outcomes = {}
    for (var i = 0; i < usable.length; i++) outcomes[usable[i].root] = "missing"
    store.emitReplied(usable, outcomes, prev, {})
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

  // The registry's usable entries, {root, name}, in registry order: an object
  // whose root is a non-empty string not starting with "-" (runs-snapshot-all.py
  // refuses any other), each root once, at its first position with its first
  // name.
  function usableRoots() {
    return Runs.usableRoots(store.projectRoots)
  }

  // byProject cut to the usable roots, each run carrying its root's current
  // project (Runs.withProject); a run that already carries it stays the same
  // object.
  function taggedByProject(byProject, usable) {
    var out = {}
    for (var i = 0; i < usable.length; i++) {
      var p = usable[i]
      if (!Runs.hasKey(byProject, p.root)) continue
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
      var list = Runs.hasKey(byProject, root) ? byProject[root] : []
      for (var j = 0; j < list.length; j++) {
        var run = list[j]
        var id = run !== null && typeof run === "object" && typeof run.id === "string" ? run.id : ""
        if (id !== "") {
          if (Runs.hasKey(owner, id)) continue
          owner[id] = root
        }
        out.push(run)
      }
    }
    return { runs: out, owner: owner }
  }

  // The registry changed. First the roots no longer usable lose their runs
  // and their errors, and `runs` is merged again in the new order with the
  // new names; no snapshotReplied is emitted. Then every usable root is
  // snapshotted.
  function registryChanged() {
    var usable = store.usableRoots()
    var errors = {}
    for (var i = 0; i < usable.length; i++) {
      var root = usable[i].root
      if (Runs.hasKey(store.projectErrors, root)) errors[root] = store.projectErrors[root]
    }
    var byProject = store.taggedByProject(store.runsByProject, usable)
    store.runsByProject = byProject
    store.projectErrors = errors
    store.runs = store.mergedRuns(byProject, usable).runs
    store.refresh()
  }

  onProjectRootsChanged: store.registryChanged()

  // ---- attempt logs (5.2)

  // The run with this id in the snapshot, or null.
  function runById(id) {
    return Runs.runById(store.runs, id)
  }

  // The run's project root when it is a non-empty string, else "".
  function runRoot(run) {
    return Runs.runRoot(run)
  }

  // Shows (and fetches) one attempt or one step of the selected run. A step is
  // (cardId, phase, 0, true) -- `step` exactly true, attempt exactly 0 -- and
  // is stored as { card_id, phase, attempt: 0, step: true }; an attempt has
  // `step` anything else and a number 0 or above (0 is the phase's newest
  // output, am's choice), and is stored as { card_id, phase, attempt }.
  // Another selection than the one shown (a step and an attempt of one phase
  // differ) starts from an empty pane -- its predecessor's text is never shown
  // under its heading. Nothing happens without a selected run, a non-empty
  // card and phase, and one of those forms.
  function selectAttempt(cardId, phase, attempt, step) {
    if (store.selectedRunId === "") return
    if (typeof cardId !== "string" || cardId === "" || typeof phase !== "string" || phase === "") return
    var isStep = step === true
    if (isStep && attempt !== 0) return
    if (!isStep && (typeof attempt !== "number" || !isFinite(attempt) || attempt < 0)) return
    var old = store.selectedAttempt
    if (!old || old.card_id !== cardId || old.phase !== phase || old.attempt !== attempt
        || (old.step === true) !== isStep) {
      store.logsText = ""
      store.logsTruncated = false
      store.logsFetchedMs = 0
      store.logsError = ""
      store.logsNote = ""
    }
    store.selectedAttempt = isStep ? { card_id: cardId, phase: phase, attempt: 0, step: true }
                                   : { card_id: cardId, phase: phase, attempt: attempt }
    store.fetchLogs()
  }

  // The Refresh button: the same attempt again; the text stays until the reply.
  function refreshLogs() {
    store.fetchLogs()
  }

  // The selection's status in `run`: its phase's for a step, its attempt's otherwise.
  function selectionStatus(run, sel) {
    return sel.step === true ? Runs.phaseStatus(run, sel.card_id, sel.phase)
                             : Runs.attemptStatus(run, sel.card_id, sel.phase, sel.attempt)
  }

  // One runs-logs.py launch for the selection, the selected run's repo_dir
  // first, remembering the status it was launched for (a snapshot that changes
  // it fetches again). Nothing launches for a run not in the snapshot or one
  // with no repo_dir.
  function fetchLogs() {
    var sel = store.selectedAttempt
    if (store.selectedRunId === "" || !sel) return
    var run = store.runById(store.selectedRunId)
    if (run === null || typeof run.repo_dir !== "string" || run.repo_dir === "") return
    store.logsStatus = store.selectionStatus(run, sel)
    store.logsLoading = true
    logsRunner.run([run.repo_dir, store.selectedRunId, sel.card_id, sel.phase, String(sel.attempt)])
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
    store.logsNote = ""
    store.logsStatus = ""
    store.logsRunState = ""
  }

  // The selected run's opening selection: the attempt its stop report names,
  // else its default attempt or step. It is selected when there is one; with
  // none the selection is left alone. Either way logsRunState becomes the
  // run's Runs.runState, or "" when the run is not in the snapshot.
  function openDefaultAttempt() {
    var run = store.runById(store.selectedRunId)
    var report = Runs.stopReport(run)
    var target = report !== null && report.attempt !== null ? report.attempt : Runs.defaultAttempt(run)
    store.logsRunState = run !== null ? Runs.runState(run) : ""
    if (target) store.selectAttempt(target.card_id, target.phase, target.attempt, target.step === true)
  }

  // After every applied snapshot, for a selected run: when the run is in the
  // snapshot and its Runs.runState is not logsRunState, it opens on its
  // opening selection again, over any selection picked since; otherwise a run
  // with no selection yet gets its opening selection once one exists, and the
  // selection is fetched again only when its status (a step's phase status,
  // an attempt's own) moved since its fetch was launched. Nothing else
  // fetches logs on its own.
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
    var status = store.selectionStatus(run, sel)
    if (status !== store.logsStatus) store.fetchLogs()
  }

  // Another run (or none): the pane starts over, a selected run opens on its
  // opening attempt, the events start over (selectEvents) and the tab is
  // Output.
  onSelectedRunIdChanged: {
    store.clearLogs()
    if (store.selectedRunId !== "") store.openDefaultAttempt()
    store.selectEvents()
    store.detailTab = "output"
  }

  // "output" or "events": sets detailTab and returns true; anything else
  // leaves it and returns false.
  function setDetailTab(tab) {
    if (tab !== "output" && tab !== "events") return false
    store.detailTab = tab
    return true
  }

  // output -> events, events -> output.
  function toggleDetailTab() {
    store.detailTab = store.detailTab === "events" ? "output" : "events"
  }

  // ---- the selected run's events (3.1)

  // No events held and no follow-up queued; then the selected run's last 200
  // are fetched, or, with no run selected, the fetch in flight is stopped and
  // the status is idle.
  function selectEvents() {
    eventsState.followUp = false
    store.events = []
    store.eventsDropped = 0
    store.eventsCursor = 0
    store.eventsError = ""
    if (store.selectedRunId === "") {
      eventsRunner.cancel()
      store.eventsStatus = "idle"
      return
    }
    store.fetchEvents()
  }

  // The selected run fetched again; the rows, eventsDropped, eventsCursor and
  // eventsError stay until the reply. Nothing without a selected run.
  function refreshEvents() {
    if (store.selectedRunId === "") return
    store.fetchEvents()
  }

  // runs-events.py RUN --tail 200 for the selected run, guarded by its id.
  function fetchEvents() {
    store.eventsStatus = "loading"
    eventsRunner.guard = store.selectedRunId
    eventsState.kind = "tail"
    eventsRunner.run([store.selectedRunId, "--tail", "200"])
  }

  // A debounce window's run ids (runsNudged). While active, with ids an array
  // holding selectedRunId: the change fetch (fetchNewEvents), or, while a
  // fetch is in flight, one follow-up queued behind it (followUpEvents); the
  // fetch in flight is left alone. The run's status is never read.
  function nudgeEvents(ids) {
    if (!store.active || store.selectedRunId === "" || !Array.isArray(ids)) return
    if (ids.indexOf(store.selectedRunId) < 0) return
    if (eventsRunner.busy) {
      eventsState.followUp = true
      return
    }
    store.fetchNewEvents()
  }

  onRunsNudged: function(ids) { store.nudgeEvents(ids) }

  // The change fetch: runs-events.py RUN --since eventsCursor, guarded by the
  // run id; with eventsCursor 0, fetchEvents (--tail 200). The rows,
  // eventsDropped, eventsCursor and eventsError stay until the reply.
  function fetchNewEvents() {
    if (store.eventsCursor <= 0) {
      store.fetchEvents()
      return
    }
    store.eventsStatus = "loading"
    eventsRunner.guard = store.selectedRunId
    eventsState.kind = "since"
    eventsRunner.run([store.selectedRunId, "--since", String(store.eventsCursor)])
  }

  // The fetch in flight ended and its reply is applied: a queued follow-up is
  // taken and, while active with a run selected, the change fetch launches
  // from the state that reply left.
  function followUpEvents() {
    if (!eventsState.followUp) return
    eventsState.followUp = false
    if (store.active && store.selectedRunId !== "") store.fetchNewEvents()
  }

  // The labels for an events reply, a fresh object: every own key of
  // `titles` holding a non-empty string, then, for each story of the
  // selected run's tree with a string card_id and a non-empty string title,
  // that title where `titles` has none. `titles` is never modified.
  function eventTitles() {
    var out = {}
    var own = store.titles
    if (own !== null && typeof own === "object" && !Array.isArray(own)) {
      for (var key in own) {
        if (Runs.hasKey(own, key) && typeof own[key] === "string" && own[key] !== "") out[key] = own[key]
      }
    }
    var run = store.runById(store.selectedRunId)
    var tree = run !== null && typeof run === "object" && run.tree !== null && typeof run.tree === "object" ? run.tree : {}
    var stories = Array.isArray(tree.stories) ? tree.stories : []
    for (var i = 0; i < stories.length; i++) {
      var s = stories[i]
      if (s === null || typeof s !== "object") continue
      if (typeof s.card_id !== "string" || typeof s.title !== "string" || s.title === "") continue
      if (!Runs.hasKey(out, s.card_id)) out[s.card_id] = s.title
    }
    return out
  }

  // One events reply, applied only while `launchedGuard` is still the
  // selected run. ok true with an events array: foldReply, unless its
  // last_seq is a non-negative integer below eventsCursor, which keeps
  // events, eventsDropped and eventsCursor. Either way ok, no error. ok
  // false: error with Runs.errorText. Anything else: error, "no usable
  // result". A failure keeps events, eventsDropped and eventsCursor. Never
  // touches any other state.
  function applyEvents(stdout, exitCode, launchedGuard) {
    if (launchedGuard !== store.selectedRunId) return
    var envelope = Results.parseEnvelope(stdout)
    if (envelope !== null && envelope.ok === true && Array.isArray(envelope.events)) {
      if (store.isSeq(envelope.last_seq) && envelope.last_seq < store.eventsCursor) {
        store.eventsStatus = "ok"
        store.eventsError = ""
        return
      }
      store.foldReply(envelope)
      return
    }
    store.eventsStatus = "error"
    if (envelope !== null && envelope.ok === false) store.eventsError = Runs.errorText(envelope)
    else store.eventsError = "The events snapshot gave no usable result (exit " + exitCode + ")."
  }

  // A good reply. Its events become RunEvents.eventRow rows, labelled from
  // eventTitles() at the local UTC offset (null rows skipped), folded into
  // the held rows, at most 500.
  // eventsDropped, after a --tail launch: (total - received) less the held
  // rows below the reply's lowest seq, at least 0, plus the rows the cap
  // removed; total is the reply's when an integer >= received, else
  // received. After a --since launch: its value plus the rows the cap
  // removed. eventsCursor: the highest of itself, a non-negative integer
  // last_seq and the held rows' seqs.
  function foldReply(envelope) {
    var list = envelope.events
    var titles = store.eventTitles()
    var offset = -new Date().getTimezoneOffset()
    var fresh = []
    var lowest = null
    for (var i = 0; i < list.length; i++) {
      var e = list[i]
      if (e !== null && typeof e === "object" && typeof e.seq === "number" && isFinite(e.seq)
          && (lowest === null || e.seq < lowest)) lowest = e.seq
      var row = RunEvents.eventRow(e, titles, offset)
      if (row !== null) fresh.push(row)
    }
    var held = store.events
    var priorBelow = 0
    for (var h = 0; h < held.length; h++) {
      if (lowest !== null && held[h].seq < lowest) priorBelow += 1
    }
    var fold = RunEvents.foldEvents(held, fresh, 500)
    var received = list.length
    var total = Number.isInteger(envelope.total) && envelope.total >= received ? envelope.total : received
    var cursor = store.eventsCursor
    if (store.isSeq(envelope.last_seq) && envelope.last_seq > cursor) cursor = envelope.last_seq
    var rows = fold.rows
    if (rows.length > 0 && rows[rows.length - 1].seq > cursor) cursor = rows[rows.length - 1].seq
    store.events = rows
    if (eventsState.kind === "since") store.eventsDropped = store.eventsDropped + fold.dropped
    else store.eventsDropped = Math.max(0, total - received - priorBelow) + fold.dropped
    store.eventsCursor = cursor
    store.eventsStatus = "ok"
    store.eventsError = ""
  }

  // One logs reply. ok:true replaces the text with its last 200 lines; a
  // step's UnknownAttemptError (am has no log for it) empties the text and
  // sets logsNote "This step records no output", with no error; any other
  // failure keeps the text and only says why. Every reply but the step's
  // UnknownAttemptError leaves logsNote "". Never touches amStatus, runs or
  // lastError: those belong to the snapshot. A reply for an older fetch never
  // gets here (the runner's latest-wins).
  function applyLogs(stdout, exitCode) {
    store.logsLoading = false
    store.logsNote = ""
    var envelope = Results.parseEnvelope(stdout)
    if (envelope !== null && envelope.ok === true) {
      var tail = Runs.logTail(envelope.data, 200)
      store.logsText = tail.text
      store.logsTruncated = tail.truncated
      store.logsFetchedMs = Date.now()
      store.logsError = ""
      return
    }
    var sel = store.selectedAttempt
    if (envelope !== null && envelope.ok === false && sel && sel.step === true
        && envelope.error !== null && typeof envelope.error === "object"
        && envelope.error.type === "UnknownAttemptError") {
      store.logsText = ""
      store.logsTruncated = false
      store.logsError = ""
      store.logsNote = "This step records no output"
      store.logsFetchedMs = Date.now()
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
      if (key !== "status" && Runs.hasKey(entry, key)) row[key] = entry[key]
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
    var envelope = Results.parseEnvelope(stdout)
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
  // more, when it changes nothing; neither emits snapshotReplied. Every
  // matched entry AmMissing: the runs, runsByProject, projectErrors and the
  // coverage are emptied and amStatus is "missing". Otherwise an ok entry
  // replaces its root's runs and clears its error (entries that are not
  // objects are skipped); a failed one keeps its root's runs ([] when it had
  // none) and records Runs.errorText of its error; a usable root with no
  // entry keeps both. `runs` is merged again, and asOfSeq is 0 and appliedSeq
  // {id: 0} for every run in it. With an entry ok, everything after a good
  // snapshot follows, and while active a running watch whose roots are no
  // longer the usable "/" roots is started again. With none, amStatus is
  // "error" with the first failed entry's sentence, and `stale` stays as it
  // is. Last, once the state is applied, each root with a matched entry gets
  // snapshotReplied in registry order (emitReplied): "missing" for each in an
  // AmMissing reply, else "ok" for an ok entry, with the runs the merged list
  // attributes to it (ownedRuns), and "failed" for any other, with [].
  function applyProjects(entries, exitCode, launched) {
    var usable = store.usableRoots()
    var names = {}
    for (var u = 0; u < usable.length; u++) names[usable[u].root] = usable[u].name
    var matched = []
    var seen = {}
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i]
      if (e === null || typeof e !== "object" || Array.isArray(e)) continue
      if (typeof e.root !== "string" || !Runs.hasKey(names, e.root) || Runs.hasKey(seen, e.root)) continue
      seen[e.root] = true
      matched.push(e)
    }
    if (matched.length === 0) {
      var gone = true
      var roots = Array.isArray(launched) ? launched : []
      for (var g = 0; g < roots.length; g++) {
        if (Runs.hasKey(names, roots[g])) gone = false
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
    var prev = store.runsByProject
    var outcomes = {}
    if (missing) {
      store.runs = []
      store.runsByProject = {}
      store.projectErrors = {}
      store.appliedSeq = {}
      store.asOfSeq = 0
      store.amStatus = "missing"
      store.lastError = Runs.errorText(matched[0].error)
      for (var mr = 0; mr < matched.length; mr++) outcomes[matched[mr].root] = "missing"
      store.emitReplied(usable, outcomes, prev, {})
      return
    }
    var byProject = Runs.copyMap(store.runsByProject)
    var errors = Runs.copyMap(store.projectErrors)
    var anyOk = false
    var okRoots = {}
    var firstError = ""
    for (var k = 0; k < matched.length; k++) {
      var entry = matched[k]
      var root = entry.root
      if (entry.ok === true) {
        anyOk = true
        okRoots[root] = true
        outcomes[root] = "ok"
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
        outcomes[root] = "failed"
        if (!Runs.hasKey(byProject, root)) byProject[root] = []
        errors[root] = Runs.errorText(entry.error)
        if (firstError === "") firstError = errors[root]
      }
    }
    byProject = store.taggedByProject(byProject, usable)
    var merged = store.mergedRuns(byProject, usable)
    var applied = {}
    var ids = Object.keys(merged.owner)
    for (var d = 0; d < ids.length; d++) applied[ids[d]] = 0
    var after = {}
    for (var o in okRoots) after[o] = store.ownedRuns(byProject[o], merged.owner, o)
    store.runsByProject = byProject
    store.projectErrors = errors
    store.asOfSeq = 0
    store.appliedSeq = applied
    store.runs = merged.runs
    if (!anyOk) {
      store.amStatus = "error"
      store.lastError = firstError
      store.emitReplied(usable, outcomes, prev, after)
      return
    }
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
    }
    store.emitReplied(usable, outcomes, prev, after)
  }

  // snapshotReplied for each root of `usable` that `outcomes` ({root:
  // outcome}) names, in registry order: previousRuns is prev[root] ([] when it
  // had none), runs is after[root] ([] when it has none).
  function emitReplied(usable, outcomes, prev, after) {
    for (var i = 0; i < usable.length; i++) {
      var root = usable[i].root
      if (!Runs.hasKey(outcomes, root)) continue
      store.snapshotReplied(root, outcomes[root], Runs.hasKey(prev, root) ? prev[root] : [],
                            Runs.hasKey(after, root) ? after[root] : [])
    }
  }

  // The runs of `list`, in its order, that `owner` (mergedRuns' {id: root})
  // attributes to `root`; a run without an owned id is no root's.
  function ownedRuns(list, owner, root) {
    return list.filter(function(run) {
      return run !== null && typeof run === "object" && Runs.hasKey(owner, run.id) && owner[run.id] === root
    })
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

  // The selected run's events helper. Guard: the run id a fetch was launched
  // for, never the open project. A newer fetch wins over an older one, and a
  // reply is applied only while its run is still the selected one; then a
  // queued follow-up launches (followUpEvents).
  HelperRunner {
    id: eventsRunner
    script: store.backendDir + "runs/runs-events.py"
    onFinished: function(stdout, exitCode, launchedGuard) {
      store.applyEvents(stdout, exitCode, launchedGuard)
      store.followUpEvents()
    }
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

  // The selected run's events fetches' own state; kept apart so consumers
  // cannot write it. `kind` is the newest launch's: "tail" (RUN --tail 200)
  // or "since" (RUN --since eventsCursor). `followUp`: one change fetch
  // waits behind the fetch in flight.
  QtObject {
    id: eventsState
    property string kind: "tail"
    property bool followUp: false
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
