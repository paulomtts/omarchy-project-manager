import QtQml
import Quickshell
import Quickshell.Io
import "../domain/board.js" as Board
import "../domain/results.js" as Results
import "../domain/runs.js" as Runs

// Dispatch (S3 3.1): starting an am run for dispatchRoot. The UI opens it
// for a target (openDispatch for a card of the open project, dispatchOpenFor
// for the current dispatchRoot, relaunchOpenFor for a stopped run's card),
// edits the form (setDispatchField) and presses Start (dispatchStart); the
// store checks the form, previews it with dispatch-preview.py and starts it
// with start-run.py, one HelperRunner per Start. `dispatchState` is idle |
// previewing | ready | refused | starting | started | failed. Every object
// here is replaced, never changed in place. It also opens from Runs with no
// root (dispatchOpenFromRuns): a probe of every usable root (board-tree.py
// --probe) gives the project step's rows; dispatchProjectPick sets
// dispatchRoot and reads its tree (board-tree.py ROOT, guarded by
// dispatchRoot), whose target rows dispatchTargetPick opens the form on; a
// failed tree read disables that project's row. A dispatch opened from Runs
// survives a project switch.
// The backend directory, the open project's root, the registry, the
// panel-open flag, the run list and the open project's run settings are
// handed to it from outside -- it never reaches for another store. It never
// reads or writes the run settings itself: it asks for the open project's
// run settings (runSettingsWanted) on each project change, and for
// dispatchRoot's when an opening is for another root, whose reply comes
// back through dispatchSettingsReplied; it asks for an ok start's values to
// be saved (runSettingsSaveRequested, for the root the start was made for),
// reads runSettings as handed in, and says a failed save of this dispatch's
// start (dispatchSaveFailed) as a notice. It also asks for a re-snapshot of
// its root (refreshRequested) and a footer sentence (noticeRequested), and
// announces a start (dispatchStarted). A project change resets a card
// dispatch; closing the panel closes it unless a start is in flight. App
// composes it as `app.runDispatch`.
Scope {
  id: dispatch

  property string backendDir: ""      // <plugin>/core/backend/
  property string project: ""         // the open project's root path; "" when none is open
  property bool active: false         // App binds this to "panel open" (app.panelOpen)
  property var runs: []               // the run store's merged run list; App binds it
  property var runSettings: ({})      // the open project's run settings; App binds it, the store never writes it
  property var projectRoots: []       // [{root, name}], the registry in its order; App binds it

  // A re-snapshot is wanted: [dispatchRoot] after a start here.
  signal refreshRequested(var roots)
  // A sentence for the footer flash.
  signal noticeRequested(string text)
  // A project's run settings are wanted: the open project on a project
  // change, dispatchRoot on an opening for another root.
  signal runSettingsWanted(var root)
  // An ok start's values are to be saved for the root it was made for.
  signal runSettingsSaveRequested(var root, var patch)

  // Closing the panel closes the dispatch; a start in flight refuses and
  // lands normally.
  onActiveChanged: if (!dispatch.active) dispatch.closeDispatch()
  // A card dispatch is the old project's, even mid-start: a start already
  // launched still runs, and its reply is no longer this dispatch's; it is
  // reset with dispatchRoot "". A dispatch opened from Runs (dispatchStep
  // not "") keeps its step, root, probe and state. Then the new project's
  // run settings are wanted (none for no project).
  onProjectChanged: {
    if (dispatch.dispatchStep === "") {
      dispatch.resetDispatch()
      dispatch.dispatchRoot = ""
    }
    if (dispatch.project !== "") dispatch.runSettingsWanted(dispatch.project)
  }
  // The registry changed: the target step follows it (dispatchRegistryChanged).
  onProjectRootsChanged: dispatch.dispatchRegistryChanged()

  property string dispatchState: "idle"
  // The project root the dispatch is for; every dispatch launch carries it;
  // "" while no dispatch has been opened since the last close or project
  // switch, and at the Runs dialog's project step.
  property string dispatchRoot: ""
  // dispatchRoot's run settings as the dispatch read them, while dispatchRoot
  // is not `project`: {} until their reply (dispatchSettingsReplied), when
  // the reply is unreadable, and after every reset.
  property var dispatchRunSettings: ({})
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
  // A start for `dispatchRoot` went: the run id, or null while am does not
  // list it yet.
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

  // Every dispatch field back to its "none" value and dispatchRunSettings
  // {}; runSettings and dispatchRoot stay. The pending check, the preview,
  // the defaults lookup and the settings read are dropped; a start already
  // launched runs on, but its reply, and its save's failure, are no longer
  // this dispatch's.
  function resetDispatch() {
    dispatchDebounceTimer.stop()
    dispatchPreviewRunner.cancel()
    dispatchDefaultsRunner.cancel()
    dispatchBook.startRunner = null
    dispatchBook.savingFor = null
    dispatchBook.touched = {}
    dispatchBook.defaultsPending = false
    dispatchBook.settingsPending = false
    dispatchBook.card = null
    dispatchBook.cardMap = null
    dispatchBook.milestone = null
    dispatch.dispatchRunSettings = {}
    dispatch.dispatchState = "idle"
    dispatch.dispatchTarget = null
    dispatch.dispatchTargetLabel = ""
    dispatch.dispatchForm = null
    dispatch.dispatchPreview = null
    dispatch.clearDispatchError()
    dispatch.dispatchRunId = ""
    dispatch.dispatchMessage = ""
  }

  // The card entry: clears the steps (a card entry has no step), opens the
  // dispatch for the open project (dispatchRoot = project) and returns
  // dispatchOpenFor's result. Refused (false, nothing changes) without a
  // project or while a start is in flight.
  function openDispatch(card, cardMap) {
    if (dispatch.project === "" || dispatch.dispatchState === "starting") return false
    dispatch.dispatchClearSteps()
    dispatch.dispatchRoot = dispatch.project
    return dispatch.dispatchOpenFor(card, cardMap)
  }

  // The run settings the dispatch reads and, after a start, merges into:
  // runSettings when dispatchRoot is the open project, else
  // dispatchRunSettings.
  function dispatchSettingsSource() {
    return dispatch.dispatchRoot === dispatch.project ? dispatch.runSettings : dispatch.dispatchRunSettings
  }

  // Runs.dispatchDefaults for the opened card with `settings` (a
  // get-run-settings object), read against dispatchRoot's runs only.
  function dispatchDefaultsFor(settings) {
    return Runs.dispatchDefaults({ defaultBranch: "", settings: settings }, dispatchBook.card, dispatchBook.cardMap,
                                 Runs.filterByProject(dispatch.runs, dispatch.dispatchRoot))
  }

  // Opens the dispatch for dispatchRoot on a brd card (as Board.indexTree()
  // leaves it) or "board", with its {id: card} map, and returns whether it
  // may be started. Refused (false, nothing changes) without a dispatchRoot
  // or while a start is in flight. Every opening sets dispatchTargetLabel
  // and records the card, cardMap and cardMap's entry for the target's
  // milestone (Runs.dispatchMilestone), or null. A target dispatchPlan does
  // not offer is `refused` at once and launches nothing; any other starts
  // from dispatchDefaultsFor(dispatchSettingsSource()) and looks up
  // dispatchRoot's default branch. When dispatchRoot is not `project`,
  // dispatchRoot's run settings are wanted too (runSettingsWanted), and
  // their reply comes back through dispatchSettingsReplied. Nothing is
  // checked before every lookup has replied.
  function dispatchOpenFor(card, cardMap) {
    if (dispatch.dispatchRoot === "" || dispatch.dispatchState === "starting") return false
    dispatch.resetDispatch()
    var plan = Runs.dispatchPlan(card, cardMap)
    var milestone = Runs.dispatchMilestone(card, cardMap)
    var isMap = cardMap !== null && typeof cardMap === "object"
    dispatchBook.card = card
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
    var d = dispatch.dispatchDefaultsFor(dispatch.dispatchSettingsSource())
    dispatch.dispatchForm = { base: d.base, prefix: d.prefix, verify: d.verify, parallelism: d.parallelism,
                           allowNoVerification: d.allowNoVerification }
    dispatch.dispatchState = "previewing"
    dispatchBook.defaultsPending = true
    dispatchBook.settingsPending = dispatch.dispatchRoot !== dispatch.project
    dispatchDefaultsRunner.run(["--defaults", dispatch.dispatchRoot])
    if (dispatchBook.settingsPending) dispatch.runSettingsWanted(dispatch.dispatchRoot)
    return true
  }

  // Back to idle, dispatchRoot back to "" and the steps cleared
  // (dispatchClearSteps). Refused (false, nothing changes) while a start is
  // in flight: its outcome must land in a dialog that still shows what was
  // started.
  function closeDispatch() {
    if (dispatch.dispatchState === "starting") return false
    dispatch.resetDispatch()
    dispatch.dispatchRoot = ""
    dispatch.dispatchClearSteps()
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
  // the dispatch afresh for the same dispatchRoot on the milestone card and
  // cardMap recorded at the story's opening and returns dispatchOpenFor's
  // result. Refused (false, nothing changes) in any other state or refusal.
  function retargetToMilestone() {
    if (dispatch.dispatchState !== "refused" || dispatch.dispatchSuggest === null) return false
    return dispatch.dispatchOpenFor(dispatchBook.milestone, dispatchBook.cardMap)
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
    return Runs.verifyCommands(form)
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
    if (branch !== "" && !Runs.hasKey(dispatchBook.touched, "base")) dispatch.dispatchForm = dispatch.withField(dispatch.dispatchForm, "base", branch)
    dispatch.checkDispatch()
  }

  // root's run settings were read (App routes run control's
  // runSettingsLoaded here). For dispatchRoot, while it is not `project`:
  // `settings` becomes dispatchRunSettings ({} when not an object); prefix,
  // verify and parallelism are taken from dispatchDefaultsFor with it,
  // except a field the user set since the opening; base and
  // allowNoVerification stay. Then the form is checked. Dropped for another
  // root, and unless previewing with the read still pending.
  function dispatchSettingsReplied(root, settings) {
    if (root !== dispatch.dispatchRoot || !dispatchBook.settingsPending || dispatch.dispatchState !== "previewing") return
    dispatchBook.settingsPending = false
    if (settings === null || typeof settings !== "object") settings = {}
    dispatch.dispatchRunSettings = settings
    var d = dispatch.dispatchDefaultsFor(settings)
    var form = dispatch.dispatchForm
    var fields = ["prefix", "verify", "parallelism"]
    for (var i = 0; i < fields.length; i++) {
      if (!Runs.hasKey(dispatchBook.touched, fields[i])) form = dispatch.withField(form, fields[i], d[fields[i]])
    }
    dispatch.dispatchForm = form
    dispatch.checkDispatch()
  }

  // The form is checked: an invalid one is refused and launches nothing, a
  // subtask is ready (am has no dry run for one card), a milestone, a story
  // or the board is previewed. Waits for the defaults lookup and the
  // settings read; whichever replies last checks.
  function checkDispatch() {
    if (dispatchBook.defaultsPending || dispatchBook.settingsPending || dispatch.dispatchState !== "previewing") return
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
    dispatchPreviewRunner.run([dispatch.dispatchRoot].concat(dispatch.dispatchTargetArgs(), dispatch.dispatchOptionArgs()))
  }

  // The newest preview's reply for this dispatchRoot and these values (a form
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
    var touched = Runs.copyMap(dispatchBook.touched)
    touched[name] = true
    dispatchBook.touched = touched
    dispatch.dispatchState = "previewing"
    dispatch.dispatchPreview = null
    dispatch.clearDispatchError()
    dispatchPreviewRunner.cancel()
    dispatchDebounceTimer.restart()
    return true
  }

  // Start: only from ready. start-run.py <dispatchRoot> runs on a
  // HelperRunner of its own (guard "", madeFor dispatchRoot), which no
  // preview, project switch or other Start stops. The settings a successful
  // start saves are fixed now, from dispatchSettingsSource(): the non-blank
  // verify commands sent, the opt-out, the prefix sent followed by the
  // stored history without it (at most 20), the parallelism and, for a story
  // or milestone whose milestone card is known, prefixByMilestone
  // {<milestone id>: prefix sent}.
  function dispatchStart() {
    if (dispatch.dispatchState !== "ready") return false
    var form = dispatch.dispatchForm
    var prefix = form.prefix.trim()
    var history = [prefix]
    var source = dispatch.dispatchSettingsSource()
    var stored = Array.isArray(source.prefixHistory) ? source.prefixHistory : []
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
    var runner = dispatchStartC.createObject(dispatch, { madeFor: dispatch.dispatchRoot, savedJson: JSON.stringify(saved) })
    dispatchBook.runners = dispatchBook.runners.concat([runner])
    dispatchBook.startRunner = runner
    dispatch.dispatchState = "starting"
    runner.run([dispatch.dispatchRoot].concat(dispatch.dispatchTargetArgs(), dispatch.dispatchOptionArgs()))
    return true
  }

  // A start runner's reply is this dispatch's: it was made for the current
  // dispatchRoot and is the runner that put the store into `starting` (an
  // idle reset, and so a project switch, forgets it).
  function isHereStart(runner) {
    return runner.madeFor === dispatch.dispatchRoot && dispatchBook.startRunner === runner
  }

  // start-run.py's reply; the runner then goes. Any ok start, wherever it
  // was made, asks for its saved values to be saved for the root it was made
  // for (runSettingsSaveRequested(madeFor, patch)). When it is this
  // dispatch's: ok gives the run id and message, the saved values merged into
  // dispatchRunSettings when dispatchRoot is not `project` (prefixByMilestone
  // merged per milestone id; the open project's come back as runSettings),
  // that save request (watched by dispatchSaveFailed), `started`, a snapshot
  // of [dispatchRoot] only (refreshRequested([dispatchRoot])) and
  // dispatchStarted(id or null); a StoryBlockedError gives `refused` with
  // am's message, no log fields and the blockedSuggest() milestone; anything
  // else gives `failed` with what the helper said. A start that is not ok
  // asks for no save.
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
        if (dispatch.dispatchRoot !== dispatch.project) {
          var settings = Runs.copyMap(dispatch.dispatchRunSettings)
          for (var key in patch) {
            settings[key] = key === "prefixByMilestone" ? Runs.mergedPrefixes(settings.prefixByMilestone, patch[key]) : patch[key]
          }
          dispatch.dispatchRunSettings = settings
        }
        dispatchBook.savingFor = { root: runner.madeFor, json: runner.savedJson }
        dispatch.runSettingsSaveRequested(runner.madeFor, patch)
        dispatch.dispatchState = "started"
        dispatch.refreshRequested([dispatch.dispatchRoot])
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
  // dispatch's ok start -- its dispatchRoot, the same values -- and only
  // once. A reset forgets that save.
  function dispatchSaveFailed(root, patch) {
    var saving = dispatchBook.savingFor
    if (saving === null || saving.root !== root || root !== dispatch.dispatchRoot || saving.json !== JSON.stringify(patch)) return
    dispatchBook.savingFor = null
    dispatch.noticeRequested("Dispatch settings could not be saved")
  }

  // A start runner's work is over: it leaves dispatchStartRunners and is destroyed.
  function dropStartRunner(runner) {
    dispatchBook.runners = dispatchBook.runners.filter(function(r) { return r !== runner })
    if (dispatchBook.startRunner === runner) dispatchBook.startRunner = null
    runner.destroy()
  }

  // dispatch-preview.py --defaults, once per opening. Guarded by
  // dispatchRoot: a reply for a root the dispatch has left is dropped.
  HelperRunner {
    id: dispatchDefaultsRunner
    script: dispatch.backendDir + "runs/dispatch-preview.py"
    guard: dispatch.dispatchRoot
    onFinished: function(stdout, exitCode) { dispatch.dispatchDefaultsReplied(stdout) }
  }

  // The dispatch preview; latest wins, and every form change cancels it.
  // Guarded by dispatchRoot.
  HelperRunner {
    id: dispatchPreviewRunner
    script: dispatch.backendDir + "runs/dispatch-preview.py"
    guard: dispatch.dispatchRoot
    onFinished: function(stdout, exitCode) { dispatch.dispatchPreviewReplied(stdout) }
  }

  // ---- dispatch: project and target steps

  // The Runs dialog's step: project | target | form; "" when the dispatch
  // was not opened from Runs (idle or a card entry).
  property string dispatchStep: ""
  // The latest board-tree.py --probe envelope ({ok: true, projects}) while a
  // step is open; null before its reply, when the reply is unreadable and
  // whenever the steps are cleared.
  property var dispatchProjectProbe: null
  // The project step's rows: Runs.dispatchProjects over the usable roots,
  // the probe entries (dispatchProbeEntries) and the open project while a
  // step is open, else [].
  readonly property var dispatchProjectRows: dispatch.dispatchStep !== ""
    ? Runs.dispatchProjects(Runs.usableRoots(dispatch.projectRoots), dispatch.dispatchProbeEntries(), dispatch.project) : []
  readonly property alias dispatchProjectRunner: dispatchProjectRunner
  // The picked root's brd tree as Board.indexTree's {id: card} map: set by a
  // good tree read for dispatchRoot and kept at the target and form steps;
  // else null.
  property var dispatchTargetCardMap: null
  // The target step's rows, Runs.dispatchTargets over that tree: set and
  // kept with dispatchTargetCardMap; else [].
  property var dispatchTargetRows: []
  // A tree read is in flight: from its launch until its reply or a cancel.
  readonly property bool dispatchTargetLoading: dispatchTargetRunner.busy
  // The key of the row dispatchTargetPick took; kept by Back from the form,
  // "" whenever the target data is cleared.
  property string dispatchTargetKey: ""
  readonly property alias dispatchTargetRunner: dispatchTargetRunner
  // {root: message} for each root whose tree read failed since the dialog
  // was opened from Runs, the root as dispatchRoot held it. Its row is
  // disabled with the message as its reason, whatever the probe says.
  property var dispatchProjectFailures: ({})

  // The probe entries the project rows read: {root, ok: false, reason} for
  // each dispatchProjectFailures root, then the probe's own entries; the
  // first entry for a root wins.
  function dispatchProbeEntries() {
    var failures = dispatch.dispatchProjectFailures
    var entries = Object.keys(failures).map(function(root) { return { root: root, ok: false, reason: failures[root] } })
    var probe = dispatch.dispatchProjectProbe
    return probe !== null ? entries.concat(probe.projects) : entries
  }

  // Opens the dispatch from Runs at the project step with no root, no
  // failures and the target data cleared, and probes every usable root, in
  // registry order. Refused (false, nothing changes) while a start is in
  // flight; else true, from any state or step: a second call starts the
  // step over. With no usable root nothing is launched and the rows are [].
  function dispatchOpenFromRuns() {
    if (dispatch.dispatchState === "starting") return false
    dispatch.resetDispatch()
    dispatch.dispatchRoot = ""
    dispatch.dispatchStep = "project"
    dispatch.dispatchProjectProbe = null
    dispatch.dispatchProjectFailures = {}
    dispatch.dispatchClearTarget()
    var roots = Runs.usableRoots(dispatch.projectRoots).map(function(p) { return p.root })
    if (roots.length > 0) dispatchProjectRunner.run(["--probe"].concat(roots))
    else dispatchProjectRunner.cancel()
    return true
  }

  // The probe's reply: dispatchProjectProbe is its envelope when that is
  // {ok: true, projects: [...]}, else null (every row enabled). The exit code
  // is not read. Applied only while a step is open.
  function dispatchProjectReplied(stdout) {
    if (dispatch.dispatchStep === "") return
    var reply = Results.parseEnvelope(stdout)
    dispatch.dispatchProjectProbe = reply !== null && reply.ok === true && Array.isArray(reply.projects) ? reply : null
  }

  // Takes the project step's enabled row for `root`: dispatchRoot is the
  // row's root, the step is target, the target data is cleared and the
  // root's tree is read (board-tree.py ROOT); no defaults, settings or
  // preview is launched. Refused (false, nothing changes) at any other step
  // and for a root with no enabled row.
  function dispatchProjectPick(root) {
    if (dispatch.dispatchStep !== "project") return false
    var rows = dispatch.dispatchProjectRows
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].root !== root || rows[i].enabled !== true) continue
      dispatch.dispatchRoot = rows[i].root
      dispatch.dispatchStep = "target"
      dispatch.dispatchClearTarget()
      dispatchTargetRunner.run([dispatch.dispatchRoot])
      return true
    }
    return false
  }

  // The tree read's reply, applied only at the target step. {ok: true,
  // data: [...]} that Board.indexTree walks gives dispatchTargetCardMap and
  // dispatchTargetRows. Anything else records dispatchRoot in
  // dispatchProjectFailures with error.message trimmed (else "The board
  // could not be read"), clears the target data and goes back to the
  // project step with dispatchRoot "". The exit code is not read.
  function dispatchTargetReplied(stdout) {
    if (dispatch.dispatchStep !== "target") return
    var envelope = Results.parseEnvelope(stdout)
    var data = envelope !== null && envelope.ok === true && Array.isArray(envelope.data) ? envelope.data : null
    var cardMap = null
    if (data !== null) {
      try { cardMap = Board.indexTree(data).cardMap } catch (e) { cardMap = null }
    }
    if (cardMap !== null) {
      dispatch.dispatchTargetCardMap = cardMap
      dispatch.dispatchTargetRows = Runs.dispatchTargets(data, cardMap)
      return
    }
    var err = envelope !== null && envelope.ok !== true ? envelope.error : null
    var message = err !== null && typeof err === "object" && typeof err.message === "string" ? err.message.trim() : ""
    var failures = Runs.copyMap(dispatch.dispatchProjectFailures)
    failures[dispatch.dispatchRoot] = message !== "" ? message : "The board could not be read"
    dispatch.dispatchProjectFailures = failures
    dispatch.dispatchClearTarget()
    dispatch.dispatchStep = "project"
    dispatch.dispatchRoot = ""
  }

  // Takes the target step's row with this key: dispatchOpenFor(row.card,
  // dispatchTargetCardMap) opens S3's form for dispatchRoot, the step is
  // form and dispatchTargetKey the key; the rows and the card map stay.
  // Refused (false, nothing changes) at any other step and for a key no row
  // has. When dispatchOpenFor refuses, the dispatch is reset, the step stays
  // target and it returns false.
  function dispatchTargetPick(key) {
    if (dispatch.dispatchStep !== "target") return false
    var rows = dispatch.dispatchTargetRows
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].key !== key) continue
      if (!dispatch.dispatchOpenFor(rows[i].card, dispatch.dispatchTargetCardMap)) {
        dispatch.resetDispatch()
        return false
      }
      dispatch.dispatchTargetKey = key
      dispatch.dispatchStep = "form"
      return true
    }
    return false
  }

  // From the target step back to the project step: dispatchRoot "" and the
  // target data cleared; the probe, its rows and the failures stay and
  // nothing is relaunched. From the form back to the target step: the
  // dispatch reset (resetDispatch), dispatchRoot, the rows, the card map and
  // dispatchTargetKey kept, nothing relaunched; refused while starting.
  // Refused (false, nothing changes) at any other step.
  function dispatchBack() {
    if (dispatch.dispatchStep === "form") {
      if (dispatch.dispatchState === "starting") return false
      dispatch.resetDispatch()
      dispatch.dispatchStep = "target"
      return true
    }
    if (dispatch.dispatchStep !== "target") return false
    dispatch.dispatchClearTarget()
    dispatch.dispatchStep = "project"
    dispatch.dispatchRoot = ""
    return true
  }

  // The target data cleared: the tree read cancelled, dispatchTargetCardMap
  // null, dispatchTargetRows [] and dispatchTargetKey "".
  function dispatchClearTarget() {
    dispatchTargetRunner.cancel()
    dispatch.dispatchTargetCardMap = null
    dispatch.dispatchTargetRows = []
    dispatch.dispatchTargetKey = ""
  }

  // The steps cleared: the probe cancelled, the target data cleared,
  // dispatchStep "", dispatchProjectProbe null and dispatchProjectFailures {}.
  function dispatchClearSteps() {
    dispatchProjectRunner.cancel()
    dispatch.dispatchClearTarget()
    dispatch.dispatchStep = ""
    dispatch.dispatchProjectProbe = null
    dispatch.dispatchProjectFailures = {}
  }

  // The registry changed: at the target step, and at the form unless a
  // start is in flight, a dispatchRoot that is no longer a usable root
  // (trailing "/" removed) goes back to the project step with dispatchRoot
  // "" and the target data cleared; at the form the dispatch is reset too.
  // Any other step, and the form while starting, is left alone.
  function dispatchRegistryChanged() {
    var step = dispatch.dispatchStep
    if (step !== "target" && step !== "form") return
    if (step === "form" && dispatch.dispatchState === "starting") return
    var rows = Runs.dispatchProjects(Runs.usableRoots(dispatch.projectRoots), null, "")
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].root === dispatch.dispatchRoot) return
    }
    if (step === "form") dispatch.resetDispatch()
    dispatch.dispatchClearTarget()
    dispatch.dispatchStep = "project"
    dispatch.dispatchRoot = ""
  }

  // board-tree.py --probe ROOT... for the project step; latest wins. No
  // guard: the probe depends on no root. dispatchClearSteps() cancels it.
  HelperRunner {
    id: dispatchProjectRunner
    script: dispatch.backendDir + "boards/board-tree.py"
    onFinished: function(stdout, exitCode) { dispatch.dispatchProjectReplied(stdout) }
  }

  // board-tree.py ROOT for the target step; latest wins. Guarded by
  // dispatchRoot: a reply whose launch root is no longer dispatchRoot is
  // dropped. Back, any step clear and the registry fallback cancel it.
  HelperRunner {
    id: dispatchTargetRunner
    script: dispatch.backendDir + "boards/board-tree.py"
    guard: dispatch.dispatchRoot
    onFinished: function(stdout, exitCode) { dispatch.dispatchTargetReplied(stdout) }
  }

  // ---- relaunch

  // Opens the dispatch for card as openDispatch does and returns its result;
  // when it opens, relaunch.prefix and relaunch.base (Runs.stopReport's
  // relaunch), each when a non-blank string, are set trimmed over the
  // defaults, and a base set so is kept over the default branch (recorded as
  // touched). Refused (false, nothing changes) when card or relaunch is not
  // an object.
  function relaunchOpenFor(card, cardMap, relaunch) {
    var isObject = function(v) { return v !== null && typeof v === "object" && !Array.isArray(v) }
    if (!isObject(card) || !isObject(relaunch)) return false
    if (!dispatch.openDispatch(card, cardMap)) return false
    if (typeof relaunch.prefix === "string" && relaunch.prefix.trim() !== "")
      dispatch.dispatchForm = dispatch.withField(dispatch.dispatchForm, "prefix", relaunch.prefix.trim())
    if (typeof relaunch.base === "string" && relaunch.base.trim() !== "") {
      dispatch.dispatchForm = dispatch.withField(dispatch.dispatchForm, "base", relaunch.base.trim())
      var touched = Runs.copyMap(dispatchBook.touched)
      touched.base = true
      dispatchBook.touched = touched
    }
    return true
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
  // by an idle reset (and so by a project switch); `touched` is {field: true}
  // for each form field the user set since the opening; `defaultsPending`
  // says the --defaults lookup has not replied yet, `settingsPending` that
  // dispatchRoot's run settings read has not; `card`, `cardMap` and
  // `milestone` are the opening's card, card map and its entry for the
  // target's milestone card (null when unknown); `savingFor` is {root, json}
  // of this dispatch's ok start's save until its failure is said or a reset,
  // else null.
  QtObject {
    id: dispatchBook
    property var runners: []
    property var startRunner: null
    property var savingFor: null
    property var touched: ({})
    property bool defaultsPending: false
    property bool settingsPending: false
    property var card: null
    property var cardMap: null
    property var milestone: null
  }

  // One HelperRunner per Start. Guard "": start-run.py may take ~20 s, and
  // neither a preview, a project switch nor a Start for another root may
  // stop it. It goes when its start replies.
  Component {
    id: dispatchStartC

    HelperRunner {
      id: sr
      property string madeFor: ""     // the dispatchRoot the start was made for
      property string savedJson: ""   // `saved` as set-run-settings takes it
      script: dispatch.backendDir + "runs/start-run.py"
      guard: ""
      onFinished: function(stdout, exitCode) { dispatch.dispatchStartReplied(sr, stdout) }
    }
  }
}
