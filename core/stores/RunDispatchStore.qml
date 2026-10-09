import QtQml
import Quickshell
import Quickshell.Io
import "../domain/results.js" as Results
import "../domain/runs.js" as Runs

// Dispatch (S3 3.1): starting an am run. The UI opens it for a target
// (openDispatch), edits the form (setDispatchField) and presses Start
// (dispatchStart); the store checks the form, previews it with
// dispatch-preview.py and starts it with start-run.py, one HelperRunner per
// Start. `dispatchState` is idle | previewing | ready | refused | starting |
// started | failed. Every object here is replaced, never changed in place.
// The backend directory, the open project's root, the panel-open flag, the
// run list and the open project's run settings are handed to it from
// outside -- it never reaches for another store. It never reads or writes
// the run settings itself: it asks for the open project's run settings
// (runSettingsWanted) on each project change and for an ok start's values to
// be saved (runSettingsSaveRequested, for the project the start was made
// in), reads runSettings as handed in, and says a failed save of this
// dispatch's start (dispatchSaveFailed) as a notice. It also asks for a
// re-snapshot (refreshRequested) and a footer sentence (noticeRequested), and
// announces a start (dispatchStarted). A project change resets it; closing
// the panel closes it unless a start is in flight. App composes it as
// `app.runDispatch`.
Scope {
  id: dispatch

  property string backendDir: ""      // <plugin>/core/backend/
  property string project: ""         // the open project's root path; "" when none is open
  property bool active: false         // App binds this to "panel open" (app.panelOpen)
  property var runs: []               // the run store's merged run list; App binds it
  property var runSettings: ({})      // the open project's run settings; App binds it, the store never writes it

  // A re-snapshot is wanted: always "all" (every usable root) here.
  signal refreshRequested(var roots)
  // A sentence for the footer flash.
  signal noticeRequested(string text)
  // This project's run settings are wanted: `root` is the open project.
  signal runSettingsWanted(var root)
  // An ok start's values are to be saved for the project it was made in.
  signal runSettingsSaveRequested(var root, var patch)

  // Closing the panel closes the dispatch; a start in flight refuses and
  // lands normally.
  onActiveChanged: if (!dispatch.active) dispatch.closeDispatch()
  // The dispatch is the old project's, even mid-start: a start already
  // launched still runs, and its reply is no longer this dispatch's. Then
  // the new project's run settings are wanted (none for no project).
  onProjectChanged: {
    dispatch.resetDispatch()
    if (dispatch.project !== "") dispatch.runSettingsWanted(dispatch.project)
  }

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

  readonly property alias dispatchDefaultsRunner: dispatchDefaultsRunner
  readonly property alias dispatchPreviewRunner: dispatchPreviewRunner
  readonly property alias dispatchDebounceTimer: dispatchDebounceTimer
  readonly property alias dispatchStartRunners: dispatchBook.runners // in-flight start runners, oldest first

  // No refusal, failure or suggestion to show.
  function clearDispatchError() {
    dispatch.dispatchError = ""
    dispatch.dispatchErrorType = ""
    dispatch.dispatchErrors = []
    dispatch.dispatchLog = ""
    dispatch.dispatchLogTail = ""
    dispatch.dispatchExitCode = null
    dispatch.dispatchSuggest = null
  }

  // Every dispatch field back to its "none" value; runSettings stays. The
  // pending check, the preview and the defaults lookup are dropped; a start
  // already launched runs on, but its reply, and its save's failure, are no
  // longer this dispatch's.
  function resetDispatch() {
    dispatchDebounceTimer.stop()
    dispatchPreviewRunner.cancel()
    dispatchDefaultsRunner.cancel()
    dispatchBook.startRunner = null
    dispatchBook.savingFor = null
    dispatchBook.baseTouched = false
    dispatchBook.defaultsPending = false
    dispatchBook.cardMap = null
    dispatchBook.milestone = null
    dispatch.dispatchState = "idle"
    dispatch.dispatchTarget = null
    dispatch.dispatchTargetLabel = ""
    dispatch.dispatchForm = null
    dispatch.dispatchPreview = null
    dispatch.clearDispatchError()
    dispatch.dispatchRunId = ""
    dispatch.dispatchMessage = ""
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
    if (dispatch.project === "" || dispatch.dispatchState === "starting") return false
    dispatch.resetDispatch()
    var plan = Runs.dispatchPlan(card, cardMap)
    var milestone = Runs.dispatchMilestone(card, cardMap)
    var isMap = cardMap !== null && typeof cardMap === "object"
    dispatchBook.cardMap = cardMap
    dispatchBook.milestone = milestone !== null && isMap && Runs.hasKey(cardMap, milestone.id) ? cardMap[milestone.id] : null
    dispatch.dispatchTarget = plan
    dispatch.dispatchTargetLabel = Runs.dispatchLabel(card, cardMap)
    if (!plan.offered) {
      dispatch.dispatchState = "refused"
      dispatch.dispatchError = plan.reason
      dispatch.dispatchErrorType = "Target"
      return false
    }
    var d = Runs.dispatchDefaults({ defaultBranch: "", settings: dispatch.runSettings }, card, cardMap, dispatch.runs)
    dispatch.dispatchForm = { base: d.base, prefix: d.prefix, verify: d.verify, parallelism: d.parallelism,
                           allowNoVerification: d.allowNoVerification }
    dispatch.dispatchState = "previewing"
    dispatchBook.defaultsPending = true
    dispatchDefaultsRunner.run(["--defaults", dispatch.project])
    return true
  }

  // Back to idle. Refused while a start is in flight: its outcome must land in
  // a dialog that still shows what was started.
  function closeDispatch() {
    if (dispatch.dispatchState === "starting") return false
    dispatch.resetDispatch()
    return true
  }

  // The milestone a StoryBlockedError refusal offers: the recorded milestone
  // card as Runs.dispatchMilestone's {id, title} when the target is a story
  // and its milestone is known, else null.
  function blockedSuggest() {
    if (dispatch.dispatchTarget === null || dispatch.dispatchTarget.level !== "story" || dispatchBook.milestone === null) return null
    return Runs.dispatchMilestone(dispatchBook.milestone, dispatchBook.cardMap)
  }

  // From a blocked story's refusal (`refused` with a dispatchSuggest), opens
  // the dispatch afresh on the milestone card and cardMap recorded at the
  // story's opening and returns openDispatch's result. Refused (false,
  // nothing changes) in any other state or refusal.
  function retargetToMilestone() {
    if (dispatch.dispatchState !== "refused" || dispatch.dispatchSuggest === null) return false
    return dispatch.openDispatch(dispatchBook.milestone, dispatchBook.cardMap)
  }

  // A copy of the form with one field set as given; verify is copied as a
  // fresh array when it is one. The store converts nothing else.
  function withField(form, name, value) {
    var next = Runs.copyMap(form)
    next[name] = name === "verify" && Array.isArray(value) ? value.slice() : value
    return next
  }

  // The helpers' target words: milestone ID, card ID or board.
  function dispatchTargetArgs() {
    var plan = dispatch.dispatchTarget
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
    var form = dispatch.dispatchForm
    var args = []
    var base = typeof form.base === "string" ? form.base.trim() : ""
    if (base !== "") args.push("--base-branch", base)
    args.push("--branch-prefix", form.prefix.trim(), "--max-concurrent", String(form.parallelism))
    var commands = dispatch.dispatchCommands(form)
    for (var i = 0; i < commands.length; i++) args.push("--verify", commands[i])
    if (form.allowNoVerification === true) args.push("--allow-no-verification")
    return args
  }

  // The --defaults reply: a non-blank default branch becomes base unless the
  // user set base since the opening; anything else leaves base as it is.
  // Then the form is checked at once.
  function dispatchDefaultsReplied(stdout) {
    if (!dispatchBook.defaultsPending || dispatch.dispatchState !== "previewing") return
    dispatchBook.defaultsPending = false
    var envelope = Results.parseEnvelope(stdout)
    var data = envelope !== null && envelope.ok === true ? envelope.data : null
    var branch = data !== null && typeof data === "object" && typeof data.default_branch === "string"
        ? data.default_branch.trim() : ""
    if (branch !== "" && !dispatchBook.baseTouched) dispatch.dispatchForm = dispatch.withField(dispatch.dispatchForm, "base", branch)
    dispatch.checkDispatch()
  }

  // The form is checked: an invalid one is refused and launches nothing, a
  // subtask is ready (am has no dry run for one card), a milestone, a story
  // or the board is previewed. Waits for the defaults lookup, whose reply checks.
  function checkDispatch() {
    if (dispatchBook.defaultsPending || dispatch.dispatchState !== "previewing") return
    dispatchDebounceTimer.stop()
    var result = Runs.validateDispatch(dispatch.dispatchForm)
    if (!result.ok) {
      dispatch.dispatchState = "refused"
      dispatch.dispatchErrors = result.errors
      dispatch.dispatchError = result.errors[0].message
      dispatch.dispatchErrorType = "Form"
      return
    }
    if (dispatch.dispatchTarget.level === "subtask") {
      dispatch.dispatchState = "ready"
      return
    }
    dispatchPreviewRunner.run([dispatch.project].concat(dispatch.dispatchTargetArgs(), dispatch.dispatchOptionArgs()))
  }

  // The newest preview's reply for this project and these values (a form
  // change cancels the runner). ok: ready with Runs.previewSummary for the
  // target's level, except a story with nothing left, refused as `Nothing
  // left to run` (Empty); am's refusal: its message verbatim, and for a
  // StoryBlockedError the blockedSuggest() milestone; anything else cannot
  // be read.
  function dispatchPreviewReplied(stdout) {
    if (dispatch.dispatchState !== "previewing") return
    var envelope = Results.parseEnvelope(stdout)
    if (envelope !== null && envelope.ok === true) {
      var level = dispatch.dispatchTarget.level
      var preview = Runs.previewSummary(envelope.data, level)
      if (level === "story" && preview.summary === "Nothing left to run") {
        dispatch.dispatchState = "refused"
        dispatch.dispatchError = preview.summary
        dispatch.dispatchErrorType = "Empty"
        return
      }
      dispatch.dispatchPreview = preview
      dispatch.dispatchState = "ready"
      return
    }
    var err = envelope !== null && envelope.ok === false ? envelope.error : null
    var message = err !== null && typeof err === "object" && typeof err.message === "string" ? err.message : ""
    dispatch.dispatchState = "refused"
    if (message.trim() !== "") {
      dispatch.dispatchError = message
      dispatch.dispatchErrorType = typeof err.type === "string" ? err.type : ""
      if (dispatch.dispatchErrorType === "StoryBlockedError") dispatch.dispatchSuggest = dispatch.blockedSuggest()
    } else {
      dispatch.dispatchError = "The preview could not be read"
      dispatch.dispatchErrorType = ""
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
    var state = dispatch.dispatchState
    if (state !== "previewing" && state !== "ready" && state !== "refused" && state !== "failed") return false
    if (dispatch.dispatchForm === null) return false
    dispatch.dispatchForm = dispatch.withField(dispatch.dispatchForm, name, value)
    if (name === "base") dispatchBook.baseTouched = true
    dispatch.dispatchState = "previewing"
    dispatch.dispatchPreview = null
    dispatch.clearDispatchError()
    dispatchPreviewRunner.cancel()
    dispatchDebounceTimer.restart()
    return true
  }

  // Start: only from ready. start-run.py runs on a HelperRunner of its own
  // (guard "", madeFor this project), which no preview, project switch or
  // other Start stops. The settings a successful start saves are fixed now,
  // from this project's runSettings: the non-blank verify commands sent, the
  // opt-out, the prefix sent followed by the stored history without it (at
  // most 20), the parallelism and, for a story or milestone whose milestone
  // card is known, prefixByMilestone {<milestone id>: prefix sent}.
  function dispatchStart() {
    if (dispatch.dispatchState !== "ready") return false
    var form = dispatch.dispatchForm
    var prefix = form.prefix.trim()
    var history = [prefix]
    var stored = Array.isArray(dispatch.runSettings.prefixHistory) ? dispatch.runSettings.prefixHistory : []
    for (var i = 0; i < stored.length && history.length < 20; i++) {
      var p = stored[i]
      if (typeof p === "string" && p.trim() !== "" && p !== prefix) history.push(p)
    }
    var saved = { verify: dispatch.dispatchCommands(form), allowNoVerification: form.allowNoVerification === true,
                  prefixHistory: history, parallelism: form.parallelism }
    var level = dispatch.dispatchTarget.level
    if ((level === "story" || level === "milestone") && dispatchBook.milestone !== null) {
      var keyed = {}
      keyed[dispatchBook.milestone.id] = prefix
      saved.prefixByMilestone = keyed
    }
    var runner = dispatchStartC.createObject(dispatch, { madeFor: dispatch.project, savedJson: JSON.stringify(saved) })
    dispatchBook.runners = dispatchBook.runners.concat([runner])
    dispatchBook.startRunner = runner
    dispatch.dispatchState = "starting"
    runner.run([dispatch.project].concat(dispatch.dispatchTargetArgs(), dispatch.dispatchOptionArgs()))
    return true
  }

  // A start runner's reply is this dispatch's: it was made in the current
  // project and is the runner that put the store into `starting` (an idle
  // reset, and so a project switch, forgets it).
  function isHereStart(runner) {
    return runner.madeFor === dispatch.project && dispatchBook.startRunner === runner
  }

  // start-run.py's reply; the runner then goes. Any ok start, wherever it
  // was made, asks for its saved values to be saved for the project it was
  // made in (runSettingsSaveRequested). When it is this dispatch's: ok gives
  // the run id and message, that save request (watched by
  // dispatchSaveFailed), `started`, a re-snapshot of every root
  // (refreshRequested("all")) and dispatchStarted(id or null); a
  // StoryBlockedError gives `refused` with am's message, no log fields and
  // the blockedSuggest() milestone; anything else gives `failed` with what
  // the helper said. A start that is not ok asks for no save.
  function dispatchStartReplied(runner, stdout) {
    var here = dispatch.isHereStart(runner)
    var envelope = Results.parseEnvelope(stdout)
    if (envelope !== null && envelope.ok === true) {
      // Parsed from the JSON that is written: a var property hands back a
      // list Runs.dispatchDefaults does not take for an array.
      var patch = JSON.parse(runner.savedJson)
      if (here) {
        dispatch.dispatchRunId = typeof envelope.run_id === "string" ? envelope.run_id : ""
        dispatch.dispatchMessage = typeof envelope.message === "string" ? envelope.message : ""
        dispatchBook.savingFor = { root: runner.madeFor, json: runner.savedJson }
        dispatch.runSettingsSaveRequested(runner.madeFor, patch)
        dispatch.dispatchState = "started"
        dispatch.refreshRequested("all")
        dispatch.dispatchStarted(dispatch.dispatchRunId !== "" ? dispatch.dispatchRunId : null)
      } else {
        dispatch.runSettingsSaveRequested(runner.madeFor, patch)
      }
    } else if (here) {
      var failure = envelope !== null && envelope.ok === false ? envelope : {}
      var err = failure.error
      var isErr = err !== null && err !== undefined && typeof err === "object"
      var message = isErr && typeof err.message === "string" ? err.message : ""
      var type = isErr && typeof err.type === "string" ? err.type : ""
      var blocked = type === "StoryBlockedError"
      dispatch.dispatchState = blocked ? "refused" : "failed"
      dispatch.dispatchError = message.trim() !== "" ? message : "The launch could not be read"
      dispatch.dispatchErrorType = type
      dispatch.dispatchLog = !blocked && typeof failure.log === "string" ? failure.log : ""
      dispatch.dispatchLogTail = !blocked && typeof failure.log_tail === "string" ? failure.log_tail : ""
      dispatch.dispatchExitCode = !blocked && typeof failure.exit_code === "number" ? failure.exit_code : null
      dispatch.dispatchSuggest = blocked ? dispatch.blockedSuggest() : null
    }
    dispatch.dropStartRunner(runner)
  }

  // A save of `patch` for `root` failed (App routes run control's
  // runSettingsSaveFailed here): one notice, only when it is the save of this
  // dispatch's ok start -- the open project, the same values -- and only
  // once. A reset forgets that save.
  function dispatchSaveFailed(root, patch) {
    var saving = dispatchBook.savingFor
    if (saving === null || saving.root !== root || root !== dispatch.project || saving.json !== JSON.stringify(patch)) return
    dispatchBook.savingFor = null
    dispatch.noticeRequested("Dispatch settings could not be saved")
  }

  // A start runner's work is over: it leaves dispatchStartRunners and is destroyed.
  function dropStartRunner(runner) {
    dispatchBook.runners = dispatchBook.runners.filter(function(r) { return r !== runner })
    if (dispatchBook.startRunner === runner) dispatchBook.startRunner = null
    runner.destroy()
  }

  // dispatch-preview.py --defaults, once per opening. Guarded by the project:
  // a reply for a project the user has left is dropped.
  HelperRunner {
    id: dispatchDefaultsRunner
    script: dispatch.backendDir + "runs/dispatch-preview.py"
    guard: dispatch.project
    onFinished: function(stdout, exitCode) { dispatch.dispatchDefaultsReplied(stdout) }
  }

  // The dispatch preview; latest wins, and every form change cancels it.
  HelperRunner {
    id: dispatchPreviewRunner
    script: dispatch.backendDir + "runs/dispatch-preview.py"
    guard: dispatch.project
    onFinished: function(stdout, exitCode) { dispatch.dispatchPreviewReplied(stdout) }
  }

  // only while a change waits to be checked.
  Timer {
    id: dispatchDebounceTimer
    objectName: "dispatchDebounceTimer"
    interval: 400
    repeat: false
    onTriggered: dispatch.checkDispatch()
  }

  // The dispatch's own bookkeeping; kept apart so consumers cannot write it.
  // `startRunner` is the runner that put the store into `starting`, forgotten
  // by an idle reset (and so by a project switch); `baseTouched` says the user
  // set base since the opening; `defaultsPending` that the --defaults lookup
  // has not replied yet; `cardMap` and `milestone` are the opening's card map
  // and its entry for the target's milestone card (null when unknown);
  // `savingFor` is {root, json} of this dispatch's ok start's save until its
  // failure is said or a reset, else null.
  QtObject {
    id: dispatchBook
    property var runners: []
    property var startRunner: null
    property var savingFor: null
    property bool baseTouched: false
    property bool defaultsPending: false
    property var cardMap: null
    property var milestone: null
  }

  // One HelperRunner per Start. Guard "": start-run.py may take ~20 s, and
  // neither a preview, a project switch nor a Start in another project may
  // stop it. It goes when its start replies.
  Component {
    id: dispatchStartC

    HelperRunner {
      id: sr
      property string madeFor: ""     // the project the start was made in
      property string savedJson: ""   // `saved` as set-run-settings takes it
      script: dispatch.backendDir + "runs/start-run.py"
      guard: ""
      onFinished: function(stdout, exitCode) { dispatch.dispatchStartReplied(sr, stdout) }
    }
  }
}
