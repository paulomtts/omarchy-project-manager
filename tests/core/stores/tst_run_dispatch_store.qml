// tests/core/stores/tst_run_dispatch_store.qml
// The dispatch store: the dispatch state machine (open, the --defaults
// lookup, the debounced check and preview, Start on one runner per Start and
// that runner's settings write), the story target and retargetToMilestone,
// and the four signals it emits. Built alone, and wired to a RunStore and a
// RunControlStore the way App wires app.runDispatch, with stubbed Process
// objects standing in for every helper.
import QtQuick
import QtTest

TestCase {
  id: tc
  name: "StoresRunDispatchStore"

  property string rootA: "/home/u/my proj"
  property string rootB: "/home/u/b"
  property string snapCmd: "python3|/plugin/core/backend/runs/runs-snapshot-all.py"
  property string viewerCmd: "python3|/plugin/core/backend/projects/viewer-state.py|"

  Component { id: spyC; SignalSpy {} }

  // A RunDispatchStore built alone, with nothing bound.
  function makeDispatch() {
    var comp = Qt.createComponent("../../../core/stores/RunDispatchStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    return comp.createObject(tc, { backendDir: "/plugin/core/backend/" })
  }

  // Every {dispatch, runs, control} triple make() built.
  property var wired: []

  // A RunStore, a RunControlStore wired to it the way App wires
  // app.runControl, and a RunDispatchStore wired to both the way App wires
  // app.runDispatch: backendDir copied; project, active, runs and runSettings
  // bound to the run store's own; refreshRequested to refresh() ("all") or
  // requestSnapshot(roots); noticeRequested to the control store's flash;
  // runSettingsUpdated into the run store's runSettings. The run store's
  // dispatchStore handle is not set. Returns the dispatch store.
  function make() {
    var runsComp = Qt.createComponent("../../../core/stores/RunStore.qml")
    if (runsComp.status !== Component.Ready) { fail(runsComp.errorString()); return null }
    var store = runsComp.createObject(tc, { backendDir: "/plugin/core/backend/" })
    var controlComp = Qt.createComponent("../../../core/stores/RunControlStore.qml")
    if (controlComp.status !== Component.Ready) { fail(controlComp.errorString()); return null }
    var c = controlComp.createObject(tc, { backendDir: store.backendDir })
    c.project = Qt.binding(function() { return store.project })
    c.active = Qt.binding(function() { return store.active })
    c.runs = Qt.binding(function() { return store.runs })
    store.controlStore = c
    store.snapshotReplied.connect(function(root, outcome) { if (outcome === "ok") c.settleAfterSnapshot() })
    c.refreshRequested.connect(function(roots) {
      if (roots === "all") store.refresh()
      else store.requestSnapshot(roots)
    })
    var d = makeDispatch(); if (!d) return null
    d.backendDir = store.backendDir
    d.project = Qt.binding(function() { return store.project })
    d.active = Qt.binding(function() { return store.active })
    d.runs = Qt.binding(function() { return store.runs })
    d.runSettings = Qt.binding(function() { return store.runSettings })
    d.refreshRequested.connect(function(roots) {
      if (roots === "all") store.refresh()
      else store.requestSnapshot(roots)
    })
    d.noticeRequested.connect(function(text) { c.flash(text) })
    d.runSettingsUpdated.connect(function(settings) { store.runSettings = settings })
    tc.wired = tc.wired.concat([{ dispatch: d, runs: store, control: c }])
    return d
  }

  // The RunStore make() paired with dispatch store `d`; null when none.
  function runsOf(d) {
    for (var i = 0; i < tc.wired.length; i++) {
      if (tc.wired[i].dispatch === d) return tc.wired[i].runs
    }
    return null
  }

  // The RunControlStore make() paired with dispatch store `d`; null when none.
  function controlOf(d) {
    for (var i = 0; i < tc.wired.length; i++) {
      if (tc.wired[i].dispatch === d) return tc.wired[i].control
    }
    return null
  }

  // A root's registry entry: rootA is "alpha", rootB "beta", any other "proj".
  function rootEntry(root) {
    return { root: root, name: root === tc.rootA ? "alpha" : root === tc.rootB ? "beta" : "proj" }
  }

  // The registry of `roots`, in that order, as App hands it over.
  function registry(roots) {
    return roots.map(function(r) { return tc.rootEntry(r) })
  }

  // make() with `roots` registered and no project open: the snapshot of
  // every root is in flight.
  function makeWithRoots(roots) {
    var d = make(); if (!d) return null
    runsOf(d).projectRoots = registry(roots)
    return d
  }

  // make() with one registered project, `root`, open: its first snapshot (of
  // that root alone) and its run settings load are in flight.
  function makeWithProject(root) {
    var d = make(); if (!d) return null
    runsOf(d).projectRoots = [rootEntry(root)]
    runsOf(d).project = root
    return d
  }

  // makeWithProject(root) with the panel open.
  function activeStore(root) {
    var d = make(); if (!d) return null
    runsOf(d).active = true
    runsOf(d).projectRoots = [rootEntry(root)]
    runsOf(d).project = root
    return d
  }

  // A stubbed process's reply: its stdout, then its exit code.
  function reply(proc, text, code) {
    proc.outText = text
    proc.exited(code)
  }

  // A process's argv, joined with "|".
  function argv(proc) { return proc.command.join("|") }

  // A timer firing on its own: a one-shot timer has stopped by the time its
  // triggered() is emitted.
  function fire(timer) {
    if (!timer.repeat) timer.stop()
    timer.triggered()
  }

  function ctlFail(type, message) {
    return JSON.stringify({ ok: false, error: { type: type, message: message } }) + "\n"
  }

  // runs-snapshot-all.py's reply line: {"ok": true, "projects": projects, "data_dir"}.
  function allReply(projects) {
    return JSON.stringify({ ok: true, projects: projects, data_dir: "/home/u/.local/share" }) + "\n"
  }

  // One root's entry that answered, listing `runs`.
  function okEntry(root, runs) { return { root: root, ok: true, runs: runs } }

  // A reply where every root answered: rootA's entry, then one per other
  // root the entries' repo_dir names, in first-seen order, each listing the
  // entries with that repo_dir.
  function okReply(entries) {
    var order = [tc.rootA]
    var byRoot = {}
    byRoot[tc.rootA] = []
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i]
      var root = e !== null && typeof e === "object" && typeof e.repo_dir === "string" ? e.repo_dir : tc.rootA
      if (!byRoot.hasOwnProperty(root)) {
        byRoot[root] = []
        order.push(root)
      }
      byRoot[root].push(e)
    }
    return allReply(order.map(function(r) { return tc.okEntry(r, byRoot[r]) }))
  }

  // ---- the store alone (split-runstore 4.1)

  // A bare store on project A with dispatchSettings() as its run settings and
  // milestone m1's preview landed: Start is allowed.
  function bareReady() {
    var d = makeDispatch(); if (!d) return null
    d.project = tc.rootA
    d.runSettings = JSON.parse(dispatchSettings())
    var cards = dispatchCards()
    compare(d.openDispatch(cards.m1, cards), true)
    reply(d.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(d.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(d.dispatchState, "ready")
    return d
  }

  // D-N1
  function test_a_bare_dispatch_store_is_idle_with_empty_inputs() {
    var d = makeDispatch(); if (!d) return
    checkDispatchIdle(d, "bare")
    compare(d.backendDir, "/plugin/core/backend/")
    compare(d.project, "")
    compare(d.active, false)
    compare(d.runs.length, 0)
    compare(Object.keys(d.runSettings).length, 0)
    compare(d.dispatchStartRunners.length, 0)
    compare(d.dispatchDebounceTimer.running, false)
    verify(!d.dispatchDefaultsRunner.current)
    verify(!d.dispatchPreviewRunner.current)
    var cards = dispatchCards()
    compare(d.openDispatch(cards.m1, cards), false, "no project: refused")
    checkDispatchIdle(d, "after the refused opening")
  }

  // D-N2 (A.3: the store's own active reaction)
  function test_its_own_active_closes_it_but_not_a_start() {
    var d = makeDispatch(); if (!d) return
    d.project = tc.rootA
    d.runSettings = JSON.parse(dispatchSettings())
    d.active = true
    var cards = dispatchCards()
    compare(d.openDispatch(cards.m1, cards), true)
    reply(d.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(d.dispatchState, "previewing")
    d.active = false
    checkDispatchIdle(d, "closed")

    d.active = true
    checkDispatchIdle(d, "opening the panel does nothing")
    compare(d.openDispatch(cards.m1, cards), true)
    reply(d.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(d.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(d.dispatchState, "ready")
    compare(d.dispatchStart(), true)
    var proc = d.dispatchStartRunners[0].current
    d.active = false
    compare(d.dispatchState, "starting", "a start in flight is not closed")
    compare(proc.running, true)
  }

  // D-N3 (A.3: the store's own project reaction)
  function test_its_own_project_change_resets_it_and_keeps_a_start_running() {
    var d = bareReady(); if (!d) return
    var started = spyC.createObject(tc, { target: d, signalName: "dispatchStarted" })
    var refresh = spyC.createObject(tc, { target: d, signalName: "refreshRequested" })
    var updated = spyC.createObject(tc, { target: d, signalName: "runSettingsUpdated" })
    compare(d.dispatchStart(), true)
    var runner = d.dispatchStartRunners[0]
    var proc = runner.current
    d.project = tc.rootB
    checkDispatchIdle(d, "after the switch from starting")
    compare(proc.running, true, "the start is not stopped")
    reply(proc, startOk("r-1", ""), 0)
    checkDispatchIdle(d, "after A's late start")
    compare(started.count, 0)
    compare(refresh.count, 0)
    compare(updated.count, 0)
    compare(argv(runner.current), tc.viewerCmd + "set-run-settings|/home/u/my proj|" + tc.savedJson, "recorded against A")
  }

  // D-N4 (the coupling order of an ok start)
  function test_a_start_reply_emits_settings_then_refresh_then_started() {
    var d = bareReady(); if (!d) return
    var record = []
    var payload = null
    var stateAtSettings = ""
    var stateAtStarted = ""
    d.runSettingsUpdated.connect(function(settings) {
      record.push("settings")
      payload = settings
      stateAtSettings = d.dispatchState
    })
    d.refreshRequested.connect(function(roots) { record.push("refresh:" + JSON.stringify(roots)) })
    d.dispatchStarted.connect(function(runId) {
      record.push("started:" + runId)
      stateAtStarted = d.dispatchState
    })
    compare(d.dispatchStart(), true)
    reply(d.dispatchStartRunners[0].current, startOk("r-1", ""), 0)
    compare(JSON.stringify(record), JSON.stringify(["settings", 'refresh:"all"', "started:r-1"]))
    compare(stateAtSettings, "starting", "the settings are announced before started")
    compare(stateAtStarted, "started")
    compare(payload.prefixHistory.join(","), "old")
    compare(payload.parallelism, 4)
    compare(payload.confirmDispatch, true, "a key the start does not write is kept")
    compare(payload.prefixByMilestone.m1, "old")
  }

  // D-N5 (Review Focus 3)
  function test_the_store_never_writes_its_own_run_settings() {
    var d = makeDispatch(); if (!d) return
    var s = JSON.parse(dispatchSettings())
    d.project = tc.rootA
    d.runSettings = s
    var cards = dispatchCards()
    d.openDispatch(cards.m1, cards)
    reply(d.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(d.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(d.dispatchStart(), true)
    var runner = d.dispatchStartRunners[0]
    reply(runner.current, startOk("r-1", ""), 0)
    compare(d.dispatchState, "started")
    verify(d.runSettings === s, "the input is left as it was handed over")
    compare(d.runSettings.prefixByMilestone, undefined)
    reply(runner.current, JSON.stringify({ ok: true }) + "\n", 0)
    verify(d.runSettings === s)
  }

  // D-N6 (A.3: the notice)
  function test_a_failed_settings_write_emits_one_notice_only_while_here() {
    var d = bareReady(); if (!d) return
    var notices = spyC.createObject(tc, { target: d, signalName: "noticeRequested" })
    d.dispatchStart()
    var runner = d.dispatchStartRunners[0]
    reply(runner.current, startOk("r-1", ""), 0)
    compare(notices.count, 0, "nothing to say before the write replies")
    reply(runner.current, "garbage\n", 1)
    compare(notices.count, 1)
    compare(notices.signalArguments[0][0], "Dispatch settings could not be saved")
    compare(d.dispatchStartRunners.length, 0)

    var left = bareReady(); if (!left) return
    var leftNotices = spyC.createObject(tc, { target: left, signalName: "noticeRequested" })
    left.dispatchStart()
    var leftRunner = left.dispatchStartRunners[0]
    left.project = tc.rootB
    reply(leftRunner.current, startOk("r-2", ""), 0)
    reply(leftRunner.current, "garbage\n", 1)
    compare(leftNotices.count, 0, "no notice about A once the project changed")
    compare(left.dispatchStartRunners.length, 0)

    var ok = bareReady(); if (!ok) return
    var okNotices = spyC.createObject(tc, { target: ok, signalName: "noticeRequested" })
    ok.dispatchStart()
    var okRunner = ok.dispatchStartRunners[0]
    reply(okRunner.current, startOk("r-3", ""), 0)
    reply(okRunner.current, JSON.stringify({ ok: true }) + "\n", 0)
    compare(okNotices.count, 0, "a saved write says nothing")
  }
  // ---- dispatch (S3 3.1)

  property string previewCmd: "python3|/plugin/core/backend/runs/dispatch-preview.py|"
  property string startCmd: "python3|/plugin/core/backend/runs/start-run.py|"

  // get-run-settings with every key, as viewer-state.py prints it.
  function dispatchSettings() {
    return JSON.stringify({ verify: ["uv run pytest"], allowNoVerification: false, notifyOnEscalation: false,
                            prefixHistory: ["old"], parallelism: 4, confirmDispatch: true }) + "\n"
  }

  // A milestone, its story, the story's subtask and a done milestone, as
  // Board.indexTree() leaves them; the object is also their {id: card} map.
  function dispatchCards() {
    return {
      m1: { id: "m1", title: "M3 Document runs", status: "todo", parentId: "", depth: 0 },
      s1: { id: "s1", title: "Dispatch store", status: "todo", parentId: "m1", depth: 1 },
      t1: { id: "t1", title: "RunStore dispatch", status: "todo", parentId: "s1", depth: 2 },
      d1: { id: "d1", title: "M2 Monitor runs", status: "done", parentId: "", depth: 0 }
    }
  }

  // Project A with its run settings read (dispatchSettings).
  function dispatchStore() {
    var store = makeWithProject(rootA); if (!store) return null
    reply(runsOf(store).runSettingsRunner.current, dispatchSettings(), 0)
    return store
  }

  // Every dispatch field at its "none" value.
  function checkDispatchIdle(store, label) {
    compare(store.dispatchState, "idle", label + ": state")
    compare(store.dispatchTarget, null, label + ": target")
    compare(store.dispatchForm, null, label + ": form")
    compare(store.dispatchPreview, null, label + ": preview")
    compare(store.dispatchError, "", label + ": error")
    compare(store.dispatchErrorType, "", label + ": error type")
    compare(store.dispatchErrors.length, 0, label + ": errors")
    compare(store.dispatchSuggest, null, label + ": suggest")
    compare(store.dispatchRunId, "", label + ": run id")
    compare(store.dispatchMessage, "", label + ": message")
    compare(store.dispatchLog, "", label + ": log")
    compare(store.dispatchLogTail, "", label + ": log tail")
    compare(store.dispatchExitCode, null, label + ": exit code")
    compare(store.dispatchTargetLabel, "", label + ": target label")
  }

  // 1 (dispatchStart() from idle is checked in Task 5's test 21)
  function test_dispatch_starts_idle() {
    var store = make(); if (!store) return
    checkDispatchIdle(store, "fresh")
    compare(store.dispatchStartRunners.length, 0)
    compare(store.dispatchDebounceTimer.running, false)
    verify(!store.dispatchDefaultsRunner.current)
    verify(!store.dispatchPreviewRunner.current)
    compare(store.closeDispatch(), true, "closing an idle dispatch is fine")
    checkDispatchIdle(store, "after close")
  }

  // 2
  function test_open_without_project_is_refused() {
    var store = make(); if (!store) return
    var cards = dispatchCards()
    compare(store.openDispatch(cards.m1, cards), false)
    checkDispatchIdle(store, "no project")
    verify(!store.dispatchDefaultsRunner.current, "no defaults lookup")
  }

  // 3
  function test_open_milestone_goes_previewing_and_asks_defaults() {
    var store = makeWithProject(rootA); if (!store) return
    reply(runsOf(store).runSettingsRunner.current, JSON.stringify({ verify: ["uv run pytest", "  "], allowNoVerification: true,
      notifyOnEscalation: false, prefixHistory: [], parallelism: 6, confirmDispatch: true }) + "\n", 0)
    var cards = dispatchCards()
    compare(store.openDispatch(cards.m1, cards), true)
    compare(store.dispatchState, "previewing")
    compare(store.dispatchTarget.level, "milestone")
    compare(store.dispatchTarget.command, "milestone")
    var proc = store.dispatchDefaultsRunner.current
    verify(proc, "the default branch is looked up")
    compare(proc.command.length, 4)
    compare(argv(proc), tc.previewCmd + "--defaults|/home/u/my proj")
    compare(proc.command[3], "/home/u/my proj", "the root with a space is one argument")
    compare(proc.launchGuard, "/home/u/my proj")
    var form = store.dispatchForm
    compare(Object.keys(form).sort().join(","), "allowNoVerification,base,parallelism,prefix,verify")
    compare(form.base, "", "no base until the lookup replies")
    compare(form.prefix, "m3")
    compare(form.verify.length, 1, "the stored non-blank commands")
    compare(form.verify[0], "uv run pytest")
    compare(form.parallelism, 6)
    compare(form.allowNoVerification, false, "the opt-out is never pre-ticked")
    verify(!store.dispatchPreviewRunner.current, "no preview before the default branch is known")
    compare(store.dispatchDebounceTimer.running, false)
  }

  function test_open_before_the_settings_reply_starts_from_nothing() {
    var store = makeWithProject(rootA); if (!store) return
    var cards = dispatchCards()
    compare(store.openDispatch(cards.m1, cards), true)
    compare(store.dispatchForm.verify.length, 0)
    compare(store.dispatchForm.parallelism, 4)
    reply(runsOf(store).runSettingsRunner.current, dispatchSettings(), 0)
    compare(store.dispatchForm.verify.length, 0, "a late settings reply does not touch the open form")
    compare(store.runSettings.verify[0], "uv run pytest", "but it is kept for the next opening")
  }

  // 4
  function test_open_story_is_offered_with_the_story_flag() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    compare(store.openDispatch(cards.s1, cards), true)
    compare(store.dispatchState, "previewing")
    compare(store.dispatchTarget.level, "story")
    compare(store.dispatchTarget.command, "story")
    compare(JSON.stringify(store.dispatchTarget.flags), JSON.stringify(["--story", "s1"]))
    compare(store.dispatchSuggest, null)
    compare(store.dispatchError, "")
    verify(store.dispatchForm, "an offered target has a form")
    compare(store.dispatchForm.prefix, "old", "the history's first prefix names the story's prefix")
    var proc = store.dispatchDefaultsRunner.current
    verify(proc, "the default branch is looked up")
    compare(proc.running, true)
  }

  // 5
  function test_open_done_card_is_refused() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    compare(store.openDispatch(cards.d1, cards), false)
    compare(store.dispatchState, "refused")
    compare(store.dispatchError, "The card is done")
    compare(store.dispatchErrorType, "Target")
    compare(store.dispatchSuggest, null)
    compare(store.openDispatch(null, cards), false)
    compare(store.dispatchError, "No card to dispatch")
    verify(!store.dispatchDefaultsRunner.current, "nothing launched")
  }

  function test_close_and_reopen_drop_the_pending_lookup() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    var first = store.dispatchDefaultsRunner.current
    compare(store.closeDispatch(), true)
    checkDispatchIdle(store, "closed")
    compare(first.running, false, "the lookup is stopped")
    store.openDispatch(cards.d1, cards)
    compare(store.dispatchState, "refused")
    compare(store.openDispatch(cards.m1, cards), true, "opening again replaces a refused target")
    compare(store.dispatchState, "previewing")
    compare(store.dispatchError, "")
    compare(store.dispatchErrorType, "")
    compare(store.dispatchSuggest, null)
    verify(store.dispatchDefaultsRunner.current !== first, "a fresh lookup per opening")
  }

  function defaultsOk(branch) {
    return JSON.stringify({ ok: true, data: { default_branch: branch, source: "origin/HEAD" } }) + "\n"
  }

  function previewOk(data) { return JSON.stringify({ ok: true, data: data }) + "\n" }

  // `am run --milestone m1 --dry-run` data: 2 levels, 3 subtasks, 1 story already done.
  function dispatchDryRun() {
    return {
      max_concurrent: 4,
      levels: [
        { level: 0, concurrent: 1, stories: [{ story: "s1", title: "Dispatch store", root: "main", subtasks: [
          { id: "t1", title: "RunStore dispatch", status: "todo", branch: "m3-t1", base: "main" },
          { id: "t2", title: "Docs", status: "todo", branch: "m3-t2", base: "m3-t1" }] }] },
        { level: 1, concurrent: 1, stories: [{ story: "s2", title: "Dialog", root: "m3-s2", subtasks: [
          { id: "t3", title: "Dialog", status: "todo", branch: "m3-t3", base: "m3-s2" }] }] }
      ],
      already_done: [{ kind: "story", id: "s0", title: "Done story" }],
      integrate: { branch: "m3-integrate", worktree: "/repo/.worktrees/m3-integrate", order: [] }
    }
  }

  // Project A with milestone m1 opened and its default branch `main` read: the
  // first preview is in flight.
  function previewingStore() {
    var store = dispatchStore(); if (!store) return null
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    return store
  }

  property string previewArgs: "/home/u/my proj|milestone|m1|--base-branch|main|--branch-prefix|old|--max-concurrent|4|--verify|uv run pytest"

  // 6
  function test_defaults_reply_sets_base_and_launches_preview() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(store.dispatchForm.base, "main")
    compare(store.dispatchState, "previewing")
    compare(store.dispatchDebounceTimer.running, false, "the check runs at once, no debounce")
    var proc = store.dispatchPreviewRunner.current
    verify(proc, "a preview was launched")
    compare(argv(proc), tc.previewCmd + tc.previewArgs)
    compare(proc.command.length, 13)
    compare(proc.command[2], "/home/u/my proj", "the root with a space is one argument")
    compare(proc.command[12], "uv run pytest", "a command with spaces is one argument")
    compare(proc.launchGuard, "/home/u/my proj")
  }

  // 8 + Review Focus 2
  function test_defaults_failure_sends_no_base() {
    var replies = [JSON.stringify({ ok: false, error: { type: "NoDefaultBranch", message: "detached HEAD" } }) + "\n",
                   "Traceback: boom\n",
                   defaultsOk("   "),
                   JSON.stringify({ ok: true, data: { default_branch: null, source: "" } }) + "\n",
                   JSON.stringify({ ok: true }) + "\n"]
    for (var i = 0; i < replies.length; i++) {
      var store = dispatchStore(); if (!store) return
      var cards = dispatchCards()
      store.openDispatch(cards.m1, cards)
      reply(store.dispatchDefaultsRunner.current, replies[i], 1)
      compare(store.dispatchForm.base, "", "reply " + i + " leaves base blank")
      var proc = store.dispatchPreviewRunner.current
      verify(proc, "reply " + i + ": the check still runs")
      compare(argv(proc), tc.previewCmd + "/home/u/my proj|milestone|m1|--branch-prefix|old|--max-concurrent|4|--verify|uv run pytest",
              "reply " + i + ": no --base-branch pair")
    }
    var padded = dispatchStore(); if (!padded) return
    var map = dispatchCards()
    padded.openDispatch(map.m1, map)
    reply(padded.dispatchDefaultsRunner.current, defaultsOk("  main \n"), 0)
    compare(padded.dispatchForm.base, "main", "the branch is trimmed")
    compare(padded.dispatchPreviewRunner.current.command[6], "main")
  }

  // 10
  function test_preview_ok_goes_ready_with_summary() {
    var store = previewingStore(); if (!store) return
    compare(store.dispatchPreview, null)
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchState, "ready")
    compare(store.dispatchPreview.summary, "2 levels · 3 subtasks · 1 story already done")
    compare(store.dispatchPreview.integrate, "Integrate → m3-integrate")
    compare(store.dispatchPreview.board, false)
    compare(store.dispatchError, "")
    compare(store.dispatchErrorType, "")
  }

  // 11
  function test_preview_refusal_goes_refused_verbatim() {
    var store = previewingStore(); if (!store) return
    var message = "milestone m1 is claimed by run 20261005T010000Z-abcd (pid 77)"
    reply(store.dispatchPreviewRunner.current, ctlFail("ClaimedError", message), 0)
    compare(store.dispatchState, "refused")
    compare(store.dispatchError, message, "am's sentence, verbatim")
    compare(store.dispatchErrorType, "ClaimedError")
    compare(store.dispatchPreview, null)
    var untyped = previewingStore(); if (!untyped) return
    reply(untyped.dispatchPreviewRunner.current,
          JSON.stringify({ ok: false, error: { type: 7, message: "dependency cycle: s1 -> s2 -> s1" } }) + "\n", 0)
    compare(untyped.dispatchState, "refused")
    compare(untyped.dispatchError, "dependency cycle: s1 -> s2 -> s1")
    compare(untyped.dispatchErrorType, "", "a type that is not a string is unknown")
  }

  // 12
  function test_preview_unreadable_goes_refused() {
    var replies = ["", "Traceback: boom\n", "[1, 2]\n",
                   JSON.stringify({ ok: false, error: { type: "X", message: "  " } }) + "\n",
                   JSON.stringify({ ok: false, error: "boom" }) + "\n",
                   JSON.stringify({ ok: false, error: null }) + "\n",
                   JSON.stringify({ ok: "yes" }) + "\n"]
    for (var i = 0; i < replies.length; i++) {
      var store = previewingStore(); if (!store) return
      reply(store.dispatchPreviewRunner.current, replies[i], 1)
      compare(store.dispatchState, "refused", "reply " + i)
      compare(store.dispatchError, "The preview could not be read", "reply " + i)
      compare(store.dispatchErrorType, "", "reply " + i)
      compare(store.dispatchPreview, null, "reply " + i)
    }
  }

  // 14
  function test_invalid_form_is_refused_without_launch() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    compare(store.openDispatch("board", cards), true)
    compare(store.dispatchTarget.level, "board")
    compare(store.dispatchForm.prefix, "", "the board has no milestone title to stem")
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(store.dispatchState, "refused")
    compare(store.dispatchErrorType, "Form")
    compare(store.dispatchErrors.length, 1)
    compare(store.dispatchErrors[0].field, "prefix")
    compare(store.dispatchError, "Enter a branch prefix")
    verify(!store.dispatchPreviewRunner.current, "no preview process")
  }

  // 20 (the preview half)
  function test_subtask_goes_ready_without_preview() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    compare(store.openDispatch(cards.t1, cards), true)
    compare(store.dispatchTarget.level, "subtask")
    compare(store.dispatchForm.prefix, "old", "the history's first prefix names the subtask's prefix")
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(store.dispatchState, "ready")
    compare(store.dispatchPreview, null, "am has no dry run for one card")
    verify(!store.dispatchPreviewRunner.current, "no preview process")
  }

  function test_a_closed_dispatch_drops_the_late_defaults_reply() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    var lookup = store.dispatchDefaultsRunner.current
    store.closeDispatch()
    reply(lookup, defaultsOk("main"), 0)
    checkDispatchIdle(store, "after the late reply")
    verify(!store.dispatchPreviewRunner.current, "no preview")
  }

  // 7
  function test_defaults_reply_keeps_a_user_set_base() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    compare(store.setDispatchField("base", "develop"), true)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(store.dispatchForm.base, "develop", "the user's base wins over the lookup")
    compare(argv(store.dispatchPreviewRunner.current),
            tc.previewCmd + "/home/u/my proj|milestone|m1|--base-branch|develop|--branch-prefix|old|--max-concurrent|4|--verify|uv run pytest")
  }

  // 9
  function test_debounce_waits_for_defaults() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    compare(store.setDispatchField("prefix", "m3b"), true)
    compare(store.dispatchDebounceTimer.running, true)
    fire(store.dispatchDebounceTimer)
    verify(!store.dispatchPreviewRunner.current, "nothing launched before the default branch is known")
    compare(store.dispatchState, "previewing")
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    var proc = store.dispatchPreviewRunner.current
    verify(proc, "the defaults reply checks the form")
    compare(argv(proc), tc.previewCmd + "/home/u/my proj|milestone|m1|--base-branch|main|--branch-prefix|m3b|--max-concurrent|4|--verify|uv run pytest")

    var early = dispatchStore(); if (!early) return
    early.openDispatch(cards.m1, cards)
    early.setDispatchField("parallelism", 2)
    reply(early.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(early.dispatchDebounceTimer.running, false, "the defaults reply's check replaces the pending one")
    compare(early.dispatchPreviewRunner.current.command[10], "2")
  }

  // 13
  function test_board_preview_argv() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.openDispatch("board", cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(store.dispatchState, "refused", "the board starts with no prefix")
    compare(store.setDispatchField("prefix", " all "), true)
    fire(store.dispatchDebounceTimer)
    var proc = store.dispatchPreviewRunner.current
    verify(proc, "the board is previewed")
    compare(argv(proc), tc.previewCmd + "/home/u/my proj|board|--base-branch|main|--branch-prefix|all|--max-concurrent|4|--verify|uv run pytest")
    compare(proc.command.length, 12)
    var board = { board: true, levels: [{ level: 0, milestones: [{ milestone_id: "m1", title: "M3", branch_prefix: "m3",
                                                                   base_branch: "main", plan: dispatchDryRun() }] }] }
    reply(proc, previewOk(board), 0)
    compare(store.dispatchState, "ready")
    compare(store.dispatchPreview.summary, "1 milestone, 3 subtasks")
    compare(store.dispatchPreview.board, true)
  }

  // 15 + Review Focus 1
  function test_allow_no_verification_flag() {
    var store = previewingStore(); if (!store) return
    store.setDispatchField("verify", [])
    fire(store.dispatchDebounceTimer)
    compare(store.dispatchState, "refused", "no command and no opt-out")
    compare(store.dispatchErrors[0].field, "verify")
    store.setDispatchField("allowNoVerification", true)
    fire(store.dispatchDebounceTimer)
    compare(store.dispatchState, "previewing")
    var proc = store.dispatchPreviewRunner.current
    compare(argv(proc), tc.previewCmd + "/home/u/my proj|milestone|m1|--base-branch|main|--branch-prefix|old|--max-concurrent|4|--allow-no-verification")
    store.setDispatchField("verify", ["", "  ", "-x make check", "uv run pytest"])
    fire(store.dispatchDebounceTimer)
    proc = store.dispatchPreviewRunner.current
    compare(argv(proc), tc.previewCmd + "/home/u/my proj|milestone|m1|--base-branch|main|--branch-prefix|old|--max-concurrent|4|--verify|-x make check|--verify|uv run pytest|--allow-no-verification")
    compare(proc.command[12], "-x make check", "a command that starts with a dash is one verbatim argument")
    store.setDispatchField("allowNoVerification", "yes")
    fire(store.dispatchDebounceTimer)
    compare(store.dispatchPreviewRunner.current.command[store.dispatchPreviewRunner.current.command.length - 1], "uv run pytest",
            "only a real true sends the opt-out")
  }

  // Review Focus 4 (the form half)
  function test_a_verify_value_that_is_not_a_list_is_refused_not_thrown() {
    var store = previewingStore(); if (!store) return
    compare(store.setDispatchField("verify", "uv run pytest"), true)
    fire(store.dispatchDebounceTimer)
    compare(store.dispatchState, "refused")
    compare(store.dispatchErrors[0].field, "verify")
    store.setDispatchField("allowNoVerification", true)
    store.setDispatchField("parallelism", "4")
    fire(store.dispatchDebounceTimer)
    compare(store.dispatchState, "refused", "the store converts nothing")
    compare(store.dispatchErrors[0].field, "parallelism")
    store.setDispatchField("parallelism", 4)
    fire(store.dispatchDebounceTimer)
    compare(argv(store.dispatchPreviewRunner.current),
            tc.previewCmd + "/home/u/my proj|milestone|m1|--base-branch|main|--branch-prefix|old|--max-concurrent|4|--allow-no-verification")
  }

  // 16
  function test_change_restarts_400ms_debounce_and_one_preview_per_burst() {
    var store = previewingStore(); if (!store) return
    var timer = store.dispatchDebounceTimer
    compare(timer.objectName, "dispatchDebounceTimer")
    compare(timer.interval, 400)
    compare(timer.repeat, false)
    var first = store.dispatchPreviewRunner.current
    compare(store.setDispatchField("prefix", "a"), true)
    compare(store.dispatchState, "previewing")
    compare(store.setDispatchField("prefix", "ab"), true)
    compare(store.dispatchState, "previewing")
    compare(store.setDispatchField("parallelism", 2), true)
    compare(store.dispatchState, "previewing")
    compare(timer.running, true)
    verify(store.dispatchPreviewRunner.current === first, "nothing launched during the burst")
    compare(first.running, false, "the preview in flight was cancelled")
    fire(timer)
    var proc = store.dispatchPreviewRunner.current
    verify(proc !== first, "one preview for the burst")
    compare(argv(proc), tc.previewCmd + "/home/u/my proj|milestone|m1|--base-branch|main|--branch-prefix|ab|--max-concurrent|2|--verify|uv run pytest")
  }

  // 17
  function test_latest_preview_wins() {
    var store = previewingStore(); if (!store) return
    var first = store.dispatchPreviewRunner.current
    store.setDispatchField("parallelism", 2)
    fire(store.dispatchDebounceTimer)
    var second = store.dispatchPreviewRunner.current
    verify(second !== first, "a second preview")
    reply(first, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchState, "previewing", "the older preview's reply is dropped")
    compare(store.dispatchPreview, null)
    reply(second, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchState, "ready")
    verify(store.dispatchPreview !== null)
  }

  // 18
  function test_change_after_ready_drops_preview_and_goes_previewing() {
    var store = previewingStore(); if (!store) return
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchState, "ready")
    var form = store.dispatchForm
    var list = ["make test"]
    compare(store.setDispatchField("verify", list), true)
    list.push("rm -rf /")
    compare(store.dispatchState, "previewing")
    compare(store.dispatchPreview, null)
    compare(form.verify[0], "uv run pytest", "the old form was not changed in place")
    compare(store.dispatchForm.verify.length, 1, "verify is copied")
    compare(store.dispatchForm.verify[0], "make test")
    compare(store.dispatchForm.prefix, "old", "the other fields are kept")
    compare(store.dispatchForm.base, "main")
    compare(store.dispatchDebounceTimer.running, true)
  }

  // 19
  function test_set_unknown_field_or_while_idle_is_refused() {
    var store = dispatchStore(); if (!store) return
    compare(store.setDispatchField("prefix", "x"), false, "idle")
    compare(store.dispatchForm, null)
    var cards = dispatchCards()
    store.openDispatch(cards.d1, cards)
    compare(store.setDispatchField("prefix", "x"), false, "a refused target has no form")
    compare(store.dispatchState, "refused")
    compare(store.dispatchError, "The card is done")
    store.openDispatch(cards.m1, cards)
    compare(store.setDispatchField("branch", "x"), false, "unknown field")
    compare(store.setDispatchField("__proto__", {}), false)
    compare(store.dispatchForm.prefix, "old", "nothing changed")
    compare(store.dispatchForm.branch, undefined)
    compare(store.dispatchDebounceTimer.running, false)
  }

  function startOk(runId, message) {
    return JSON.stringify({ ok: true, pid: 4242, log: "/home/u/.local/state/am-run.log", started_at: "2026-10-05T02:14:00Z",
                            run_id: runId, message: message }) + "\n"
  }

  // Project A with milestone m1's preview landed: Start is allowed.
  function readyStore() {
    var store = previewingStore(); if (!store) return null
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    return store
  }

  property string savedJson: '{"verify":["uv run pytest"],"allowNoVerification":false,"prefixHistory":["old"],"parallelism":4,"prefixByMilestone":{"m1":"old"}}'

  // 20 (the start half)
  function test_subtask_start_argv_uses_card() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.openDispatch(cards.t1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(store.dispatchStart(), true)
    var proc = store.dispatchStartRunners[0].current
    compare(argv(proc), tc.startCmd + "/home/u/my proj|card|t1|--base-branch|main|--branch-prefix|old|--max-concurrent|4|--verify|uv run pytest")
    compare(proc.command.length, 13)
  }

  // 21 + Review Focus 3
  function test_start_refused_unless_ready() {
    var store = dispatchStore(); if (!store) return
    compare(store.dispatchStart(), false, "idle")
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    compare(store.dispatchStart(), false, "previewing")
    store.openDispatch(cards.d1, cards)
    compare(store.dispatchStart(), false, "refused")
    compare(store.dispatchStartRunners.length, 0, "no start runner")
    var fresh = make(); if (!fresh) return
    compare(fresh.dispatchStart(), false, "a fresh store")
    var ready = readyStore(); if (!ready) return
    compare(ready.dispatchStart(), true)
    compare(ready.dispatchStart(), false, "a second Start while starting")
    compare(ready.dispatchStartRunners.length, 1, "one launch for a double click")
  }

  // 22
  function test_start_argv_and_starting() {
    var store = readyStore(); if (!store) return
    compare(store.dispatchStart(), true)
    compare(store.dispatchState, "starting")
    compare(store.dispatchStartRunners.length, 1)
    var runner = store.dispatchStartRunners[0]
    compare(runner.madeFor, "/home/u/my proj")
    compare(runner.guard, "", "a preview or a project switch never stops a start")
    var proc = runner.current
    compare(argv(proc), tc.startCmd + tc.previewArgs)
    compare(proc.command.length, 13)
    compare(proc.running, true)
    compare(store.dispatchPreview.summary, "2 levels · 3 subtasks · 1 story already done", "the preview stays up while starting")
  }

  // 23
  function test_change_and_close_refused_while_starting() {
    var store = readyStore(); if (!store) return
    store.dispatchStart()
    compare(store.setDispatchField("prefix", "x"), false)
    compare(store.dispatchForm.prefix, "old")
    compare(store.closeDispatch(), false)
    var cards = dispatchCards()
    compare(store.openDispatch(cards.t1, cards), false)
    compare(store.dispatchState, "starting")
    compare(store.dispatchTarget.level, "milestone")
    compare(store.dispatchDebounceTimer.running, false)
  }

  // 24
  function test_start_ok_with_run_id_emits_and_saves() {
    var store = readyStore(); if (!store) return
    reply(runsOf(store).snapshotRunner.current, okReply([]), 0)
    var spy = spyC.createObject(tc, { target: store, signalName: "dispatchStarted" })
    store.dispatchStart()
    var runner = store.dispatchStartRunners[0]
    var seq = runsOf(store).snapshotRunner.seq
    reply(runner.current, startOk("r-1", ""), 0)
    compare(store.dispatchState, "started")
    compare(store.dispatchRunId, "r-1")
    compare(store.dispatchMessage, "")
    compare(spy.count, 1)
    compare(spy.signalArguments[0][0], "r-1")
    compare(runsOf(store).snapshotRunner.seq, seq + 1, "the runs are fetched again")
    compare(argv(runsOf(store).snapshotRunner.current), tc.snapCmd + "|" + tc.rootA)
    compare(store.dispatchStartRunners.length, 1, "the same runner writes the settings")
    verify(store.dispatchStartRunners[0] === runner)
    var save = runner.current
    compare(save.command.length, 5)
    compare(argv(save), tc.viewerCmd + "set-run-settings|/home/u/my proj|" + tc.savedJson)
    compare(store.runSettings.prefixHistory.join(","), "old")
    compare(store.runSettings.verify.join(","), "uv run pytest")
    compare(store.runSettings.parallelism, 4)
    compare(store.runSettings.allowNoVerification, false)
    compare(store.runSettings.confirmDispatch, true, "keys the start does not write are kept")
    reply(save, JSON.stringify({ ok: true }) + "\n", 0)
    compare(store.dispatchStartRunners.length, 0, "the runner goes after the write")
    compare(controlOf(store).flashText, "")
    compare(store.dispatchState, "started")
  }

  // 25 + Review Focus 5 (run id half)
  function test_start_ok_without_run_id_emits_null() {
    var ids = [null, "", 42]
    for (var i = 0; i < ids.length; i++) {
      var store = readyStore(); if (!store) return
      var spy = spyC.createObject(tc, { target: store, signalName: "dispatchStarted" })
      store.dispatchStart()
      reply(store.dispatchStartRunners[0].current, startOk(ids[i], "started, run not visible yet"), 0)
      compare(store.dispatchState, "started", "run_id " + i)
      compare(store.dispatchRunId, "", "run_id " + i)
      compare(store.dispatchMessage, "started, run not visible yet")
      compare(spy.count, 1)
      compare(spy.signalArguments[0][0], null, "run_id " + i + ": not visible yet")
    }
  }

  // 26 + Review Focus 4 (the history half)
  function test_prefix_history_dedups_and_caps_at_20() {
    var store = makeWithProject(rootA); if (!store) return
    var history = ["a", "m3", "", "  ", 7, "b"]
    for (var i = 0; i < 25; i++) history.push("p" + i)
    reply(runsOf(store).runSettingsRunner.current, JSON.stringify({ verify: ["uv run pytest"], allowNoVerification: false,
      notifyOnEscalation: false, prefixHistory: history, parallelism: 4, confirmDispatch: true }) + "\n", 0)
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    store.setDispatchField("prefix", "  m3 ")
    fire(store.dispatchDebounceTimer)
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchStart(), true)
    var runner = store.dispatchStartRunners[0]
    compare(runner.current.command[8], "m3", "the prefix is sent trimmed")
    reply(runner.current, startOk("r-1", ""), 0)
    var expected = ["m3", "a", "b"]
    for (var j = 0; j < 17; j++) expected.push("p" + j)
    var saved = JSON.parse(runner.current.command[4])
    compare(saved.prefixHistory.length, 20)
    compare(saved.prefixHistory.join(","), expected.join(","))
    compare(store.runSettings.prefixHistory.join(","), expected.join(","))

    var bare = makeWithProject(rootA); if (!bare) return
    reply(runsOf(bare).runSettingsRunner.current, "Traceback: boom\n", 1)
    bare.openDispatch(cards.m1, cards)
    reply(bare.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    bare.setDispatchField("verify", ["make test"])
    fire(bare.dispatchDebounceTimer)
    reply(bare.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(bare.dispatchStart(), true)
    var bareRunner = bare.dispatchStartRunners[0]
    reply(bareRunner.current, startOk("r-2", ""), 0)
    compare(argv(bareRunner.current), tc.viewerCmd +
            'set-run-settings|/home/u/my proj|{"verify":["make test"],"allowNoVerification":false,"prefixHistory":["m3"],"parallelism":4,"prefixByMilestone":{"m1":"m3"}}')
  }

  // 27
  function test_start_failure_goes_failed_with_log() {
    var store = readyStore(); if (!store) return
    var spy = spyC.createObject(tc, { target: store, signalName: "dispatchStarted" })
    store.dispatchStart()
    var runner = store.dispatchStartRunners[0]
    reply(runner.current, JSON.stringify({ ok: false, error: { type: "AmExited", message: "am run exited at once (exit 2)" },
      log: "/home/u/.local/state/am-run.log", pid: 4242, started_at: "2026-10-05T02:14:00Z", exit_code: 2,
      log_tail: "error: milestone m1 not found" }) + "\n", 0)
    compare(store.dispatchState, "failed")
    compare(store.dispatchError, "am run exited at once (exit 2)")
    compare(store.dispatchErrorType, "AmExited")
    compare(store.dispatchLog, "/home/u/.local/state/am-run.log")
    compare(store.dispatchLogTail, "error: milestone m1 not found")
    compare(store.dispatchExitCode, 2)
    compare(spy.count, 0)
    compare(store.dispatchStartRunners.length, 0, "no settings write after a failed start")
    compare(store.runSettings.prefixHistory.join(","), "old", "nothing saved")
    compare(store.dispatchForm.prefix, "old", "the form stays for another try")
  }

  // 28 + Review Focus 5 (exit code half)
  function test_start_unreadable_goes_failed() {
    var replies = ["", "Traceback: boom\n", JSON.stringify({ ok: "maybe" }) + "\n"]
    for (var i = 0; i < replies.length; i++) {
      var store = readyStore(); if (!store) return
      store.dispatchStart()
      reply(store.dispatchStartRunners[0].current, replies[i], 1)
      compare(store.dispatchState, "failed", "reply " + i)
      compare(store.dispatchError, "The launch could not be read", "reply " + i)
      compare(store.dispatchErrorType, "", "reply " + i)
      compare(store.dispatchLog, "", "reply " + i)
      compare(store.dispatchExitCode, null, "reply " + i)
      compare(store.dispatchStartRunners.length, 0, "reply " + i)
    }
    var blank = readyStore(); if (!blank) return
    blank.dispatchStart()
    reply(blank.dispatchStartRunners[0].current, JSON.stringify({ ok: false, error: { type: "SpawnFailed", message: " " },
      log: "/tmp/l", exit_code: "2", log_tail: 5 }) + "\n", 0)
    compare(blank.dispatchState, "failed")
    compare(blank.dispatchError, "The launch could not be read")
    compare(blank.dispatchErrorType, "SpawnFailed")
    compare(blank.dispatchLog, "/tmp/l")
    compare(blank.dispatchLogTail, "", "a log tail that is not a string")
    compare(blank.dispatchExitCode, null, "an exit code that is not a number")
  }

  // 29
  function test_failed_then_change_previews_again() {
    var store = readyStore(); if (!store) return
    store.dispatchStart()
    reply(store.dispatchStartRunners[0].current, ctlFail("ClaimedError", "claimed by r-0"), 0)
    compare(store.dispatchState, "failed")
    compare(store.dispatchErrorType, "ClaimedError")
    compare(store.dispatchStart(), false, "a failed start is not retried without a new check")
    compare(store.setDispatchField("prefix", "m3-retry"), true)
    compare(store.dispatchState, "previewing")
    compare(store.dispatchError, "")
    compare(store.dispatchErrorType, "")
    compare(store.dispatchLog, "")
    compare(store.dispatchExitCode, null)
    fire(store.dispatchDebounceTimer)
    compare(argv(store.dispatchPreviewRunner.current),
            tc.previewCmd + "/home/u/my proj|milestone|m1|--base-branch|main|--branch-prefix|m3-retry|--max-concurrent|4|--verify|uv run pytest")
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchState, "ready")
    compare(store.dispatchStart(), true)
    compare(store.dispatchStartRunners.length, 1)
  }

  // A start re-snapshots every usable root, not only the project it was made in.
  function test_a_dispatch_start_refreshes_every_usable_root() {
    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return
    runsOf(store).project = rootA
    reply(runsOf(store).runSettingsRunner.current, dispatchSettings(), 0)
    reply(runsOf(store).snapshotRunner.current, allReply([okEntry(tc.rootA, []), okEntry(tc.rootB, [])]), 0)
    var cards = dispatchCards()
    compare(store.openDispatch(cards.m1, cards), true)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchStart(), true)
    var seq = runsOf(store).snapshotRunner.seq
    reply(store.dispatchStartRunners[0].current, startOk("r-1", ""), 0)
    compare(store.dispatchState, "started")
    compare(runsOf(store).snapshotRunner.seq, seq + 1, "one snapshot")
    compare(argv(runsOf(store).snapshotRunner.current), tc.snapCmd + "|" + tc.rootA + "|" + tc.rootB)
  }

  // 30
  function test_settings_write_failure_flashes() {
    var replies = [JSON.stringify({ ok: false, error: { type: "Invalid", message: "x" } }) + "\n", "garbage\n"]
    for (var i = 0; i < replies.length; i++) {
      var store = readyStore(); if (!store) return
      store.dispatchStart()
      var runner = store.dispatchStartRunners[0]
      reply(runner.current, startOk("r-1", ""), 0)
      reply(runner.current, replies[i], 1)
      compare(controlOf(store).flashText, "Dispatch settings could not be saved", "reply " + i)
      compare(store.dispatchState, "started", "the run still started")
      compare(store.dispatchStartRunners.length, 0)
      compare(controlOf(store).notifyOnEscalation, false, "the notify switch is untouched")
      verify(!controlOf(store).settingsSaveRunner.current, "the notify switch's runner is not used")
    }
  }

  function test_started_refuses_changes_and_reopening_starts_over() {
    var store = readyStore(); if (!store) return
    store.dispatchStart()
    reply(store.dispatchStartRunners[0].current, startOk("r-1", ""), 0)
    compare(store.setDispatchField("prefix", "x"), false, "started")
    compare(store.dispatchStart(), false, "started")
    var cards = dispatchCards()
    compare(store.openDispatch(cards.m1, cards), true)
    compare(store.dispatchRunId, "")
    compare(store.dispatchState, "previewing")
    compare(store.dispatchForm.verify[0], "uv run pytest", "the next form starts from the saved values")
  }

  // 31
  function test_project_switch_resets_dispatch_and_drops_old_preview() {
    var store = previewingStore(); if (!store) return
    var preview = store.dispatchPreviewRunner.current
    runsOf(store).project = rootB
    checkDispatchIdle(store, "after the switch")
    compare(Object.keys(store.runSettings).length, 0)
    compare(preview.running, false, "A's preview is stopped")
    reply(preview, previewOk(dispatchDryRun()), 0)
    checkDispatchIdle(store, "after A's late preview")

    var pending = previewingStore(); if (!pending) return
    pending.setDispatchField("prefix", "x")
    compare(pending.dispatchDebounceTimer.running, true)
    runsOf(pending).project = rootB
    compare(pending.dispatchDebounceTimer.running, false, "no check is left pending")
    checkDispatchIdle(pending, "switch during a burst")

    var cleared = previewingStore(); if (!cleared) return
    runsOf(cleared).project = ""
    checkDispatchIdle(cleared, "no project")
  }

  // 32
  function test_start_result_belongs_to_its_project() {
    var store = readyStore(); if (!store) return
    var spy = spyC.createObject(tc, { target: store, signalName: "dispatchStarted" })
    store.dispatchStart()
    var runner = store.dispatchStartRunners[0]
    var startProc = runner.current
    runsOf(store).project = rootB
    checkDispatchIdle(store, "B after the switch from starting")
    compare(startProc.running, true, "the start is not stopped")
    compare(store.dispatchStartRunners.length, 1)
    var seq = runsOf(store).snapshotRunner.seq
    reply(startProc, startOk("r-1", ""), 0)
    checkDispatchIdle(store, "B after A's start landed")
    compare(spy.count, 0)
    compare(runsOf(store).snapshotRunner.seq, seq, "no refresh for B")
    compare(Object.keys(store.runSettings).length, 0, "B's settings do not take A's values")
    compare(argv(runner.current), tc.viewerCmd + "set-run-settings|/home/u/my proj|" + tc.savedJson, "recorded against A")
    reply(runner.current, "garbage\n", 1)
    compare(controlOf(store).flashText, "", "no flash about A in B")
    compare(store.dispatchStartRunners.length, 0)
  }

  // 32b
  function test_start_reply_after_switching_away_and_back_is_not_here() {
    var store = readyStore(); if (!store) return
    var spy = spyC.createObject(tc, { target: store, signalName: "dispatchStarted" })
    store.dispatchStart()
    var runner = store.dispatchStartRunners[0]
    runsOf(store).project = rootB
    runsOf(store).project = rootA
    checkDispatchIdle(store, "back in A")
    reply(runsOf(store).runSettingsRunner.current, dispatchSettings(), 0)
    var cards = dispatchCards()
    compare(store.openDispatch(cards.m1, cards), true)
    compare(store.dispatchState, "previewing")
    reply(runner.current, startOk("r-1", ""), 0)
    compare(store.dispatchState, "previewing", "the new dialog is not overwritten")
    compare(store.dispatchRunId, "")
    compare(spy.count, 0)
    compare(store.runSettings.prefixHistory.join(","), "old")
    compare(argv(runner.current), tc.viewerCmd + "set-run-settings|/home/u/my proj|" + tc.savedJson, "still recorded for A")
  }

  // 33
  function test_start_in_other_project_does_not_stop_the_first() {
    var store = readyStore(); if (!store) return
    store.dispatchStart()
    var procA = store.dispatchStartRunners[0].current
    runsOf(store).project = rootB
    reply(runsOf(store).runSettingsRunner.current, dispatchSettings(), 0)
    var cards = dispatchCards()
    compare(store.openDispatch(cards.m1, cards), true, "B's dispatch opens while A's start is in flight")
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchState, "ready")
    compare(store.dispatchStart(), true)
    compare(store.dispatchStartRunners.length, 2)
    compare(store.dispatchStartRunners[0].madeFor, "/home/u/my proj")
    compare(store.dispatchStartRunners[1].madeFor, "/home/u/b")
    compare(procA.running, true, "A's start is still running")
    var procB = store.dispatchStartRunners[1].current
    compare(argv(procB), tc.startCmd + "/home/u/b|milestone|m1|--base-branch|main|--branch-prefix|old|--max-concurrent|4|--verify|uv run pytest")
    reply(procA, startOk("r-a", ""), 0)
    compare(store.dispatchState, "starting", "A's reply does not land in B's dialog")
    reply(procB, startOk("r-b", ""), 0)
    compare(store.dispatchState, "started")
    compare(store.dispatchRunId, "r-b")
  }

  // 34
  function test_panel_close_closes_dispatch_but_not_a_start() {
    var store = activeStore(rootA); if (!store) return
    reply(runsOf(store).runSettingsRunner.current, dispatchSettings(), 0)
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchState, "ready")
    runsOf(store).active = false
    checkDispatchIdle(store, "closed from ready")

    runsOf(store).active = true
    store.openDispatch(cards.m1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    store.setDispatchField("prefix", "x")
    compare(store.dispatchDebounceTimer.running, true)
    runsOf(store).active = false
    compare(store.dispatchDebounceTimer.running, false, "no timer while idle")
    checkDispatchIdle(store, "closed during a burst")

    runsOf(store).active = true
    store.openDispatch(cards.m1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    store.dispatchStart()
    var proc = store.dispatchStartRunners[0].current
    runsOf(store).active = false
    compare(store.dispatchState, "starting", "a start in flight is not closed")
    compare(proc.running, true)
    reply(proc, startOk("r-1", ""), 0)
    compare(store.dispatchState, "started", "it lands normally")
    compare(store.dispatchRunId, "r-1")
  }

  // ---- dispatch: story target, retarget and keyed prefix (2.1)

  // get-run-settings like dispatchSettings(), with prefixByMilestone set to map.
  function keyedSettings(map) {
    return JSON.stringify({ verify: ["uv run pytest"], allowNoVerification: false, notifyOnEscalation: false,
                            prefixHistory: ["old"], parallelism: 4, confirmDispatch: true, prefixByMilestone: map }) + "\n"
  }

  // 2.1 test 3
  function test_open_sets_the_target_label() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.openDispatch(cards.s1, cards)
    compare(store.dispatchTargetLabel, 'Story "Dispatch store" (milestone "M3 Document runs")')
    store.openDispatch(cards.m1, cards)
    compare(store.dispatchTargetLabel, 'Milestone "M3 Document runs"')
    store.openDispatch(cards.t1, cards)
    compare(store.dispatchTargetLabel, 'Subtask "RunStore dispatch"')
    store.openDispatch("board", cards)
    compare(store.dispatchTargetLabel, "Whole board")
    store.openDispatch(null, cards)
    compare(store.dispatchTargetLabel, "No card", "a refused opening is labelled too")
    compare(store.closeDispatch(), true)
    checkDispatchIdle(store, "closed")
  }

  // 2.1 test 5
  function test_story_prefix_reads_the_snapshot_then_the_keyed_map() {
    var store = makeWithProject(rootA); if (!store) return
    reply(runsOf(store).runSettingsRunner.current, keyedSettings({ m9: "m9-map" }), 0)
    runsOf(store).runs = [{ id: "r-old", milestone_id: "m1", branch_prefix: "m3-old", started_at: "2026-10-01T00:00:00Z" },
                  { id: "r-live", milestone_id: "m1", branch_prefix: " m3-live ", started_at: "2026-10-06T00:00:00Z" },
                  { id: "r-other", milestone_id: "m2", branch_prefix: "m2-x", started_at: "2026-10-07T00:00:00Z" }]
    var cards = dispatchCards()
    store.openDispatch(cards.s1, cards)
    compare(store.dispatchForm.prefix, "m3-live", "the milestone's newest snapshot run wins")
    store.openDispatch(cards.m1, cards)
    compare(store.dispatchForm.prefix, "m3-live", "the same default serves the milestone")

    var keyed = makeWithProject(rootA); if (!keyed) return
    reply(runsOf(keyed).runSettingsRunner.current, keyedSettings({ m1: "m3-map" }), 0)
    keyed.openDispatch(cards.s1, cards)
    compare(keyed.dispatchForm.prefix, "m3-map", "the keyed map beats the prefix history")
    keyed.openDispatch(cards.t1, cards)
    compare(keyed.dispatchForm.prefix, "m3-map", "a subtask reads its root milestone's entry")
  }

  // 2.1 test 12 (the done story)
  function test_a_done_story_is_refused_and_labelled() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    cards.s1 = { id: "s1", title: "Dispatch store", status: "done", parentId: "m1", depth: 1 }
    compare(store.openDispatch(cards.s1, cards), false)
    compare(store.dispatchState, "refused")
    compare(store.dispatchError, "The card is done")
    compare(store.dispatchErrorType, "Target")
    compare(store.dispatchSuggest, null)
    compare(store.dispatchTargetLabel, 'Story "Dispatch store" (milestone "M3 Document runs")')
    verify(!store.dispatchDefaultsRunner.current, "nothing launched")
  }

  // `am run --story s1 --dry-run` data: one level, story s1 with 2 subtasks rooted on main.
  function storyDryRun() {
    return {
      max_concurrent: 4,
      levels: [{ level: 0, concurrent: 1, stories: [{ story: "s1", title: "Dispatch store", root: "main", subtasks: [
        { id: "t1", title: "RunStore dispatch", status: "todo", branch: "old-t1", base: "main" },
        { id: "t2", title: "Docs", status: "todo", branch: "old-t2", base: "old-t1" }] }] }],
      already_done: [],
      integrate: null
    }
  }

  // Project A with story s1 opened and its default branch `main` read: the
  // first preview is in flight.
  function storyPreviewingStore() {
    var store = dispatchStore(); if (!store) return null
    var cards = dispatchCards()
    store.openDispatch(cards.s1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    return store
  }

  property string storyPreviewArgs: "/home/u/my proj|story|s1|--base-branch|main|--branch-prefix|old|--max-concurrent|4|--verify|uv run pytest"

  // 2.1 test 4
  function test_story_preview_argv_and_story_summary() {
    var store = storyPreviewingStore(); if (!store) return
    var proc = store.dispatchPreviewRunner.current
    verify(proc, "a story is previewed")
    compare(argv(proc), tc.previewCmd + tc.storyPreviewArgs)
    reply(proc, previewOk(storyDryRun()), 0)
    compare(store.dispatchState, "ready")
    compare(store.dispatchPreview.summary, "2 subtasks · rooted on main")
    compare(store.dispatchPreview.integrate, "")
    compare(store.dispatchPreview.board, false)
    compare(store.dispatchError, "")
    compare(store.dispatchErrorType, "")
  }

  // 2.1 test 12 (the preview half)
  function test_a_finished_story_preview_is_refused() {
    var store = storyPreviewingStore(); if (!store) return
    reply(store.dispatchPreviewRunner.current, previewOk({ max_concurrent: 4, levels: [],
      already_done: [{ kind: "story", id: "s1", title: "Dispatch store" }], integrate: null }), 0)
    compare(store.dispatchState, "refused")
    compare(store.dispatchError, "Nothing left to run")
    compare(store.dispatchErrorType, "Empty")
    compare(store.dispatchPreview, null)
    compare(store.dispatchSuggest, null)
    compare(store.dispatchStart(), false, "Start only works from ready")
    compare(store.dispatchStartRunners.length, 0)

    var milestone = previewingStore(); if (!milestone) return
    reply(milestone.dispatchPreviewRunner.current, previewOk({ max_concurrent: 4, levels: [], already_done: [], integrate: null }), 0)
    compare(milestone.dispatchState, "ready", "a milestone with nothing left keeps its behaviour")
    compare(milestone.dispatchPreview.summary, "0 levels · 0 subtasks")
  }

  // 2.1 test 11 (the preview half)
  function test_a_claimed_story_preview_names_the_other_run() {
    var store = storyPreviewingStore(); if (!store) return
    var message = "story s1 is claimed by run r-other (pid 77)"
    reply(store.dispatchPreviewRunner.current, ctlFail("ClaimedError", message), 0)
    compare(store.dispatchState, "refused")
    compare(store.dispatchError, message, "am's sentence, verbatim")
    compare(store.dispatchErrorType, "ClaimedError")
    compare(store.dispatchSuggest, null)
    compare(store.dispatchPreview, null)
  }

  property string blockedMessage: "story s1 is blocked by s0 (todo); dispatch milestone m1 instead"

  // Every dispatch field, as one string to compare before and after.
  function dispatchFields(store) {
    return JSON.stringify([store.dispatchState, store.dispatchTarget, store.dispatchTargetLabel, store.dispatchForm,
                           store.dispatchPreview, store.dispatchError, store.dispatchErrorType, store.dispatchErrors,
                           store.dispatchSuggest, store.dispatchRunId, store.dispatchMessage, store.dispatchLog,
                           store.dispatchLogTail, store.dispatchExitCode])
  }

  // retargetToMilestone() returns false, changes no dispatch field and launches no lookup.
  function checkRetargetRefused(store, label) {
    var before = dispatchFields(store)
    var lookup = store.dispatchDefaultsRunner.current
    compare(store.retargetToMilestone(), false, label)
    compare(dispatchFields(store), before, label + ": nothing changed")
    verify(store.dispatchDefaultsRunner.current === lookup, label + ": no lookup")
  }

  // 2.1 test 8
  function test_retarget_from_a_blocked_preview() {
    var store = storyPreviewingStore(); if (!store) return
    reply(store.dispatchPreviewRunner.current, ctlFail("StoryBlockedError", tc.blockedMessage), 0)
    compare(store.dispatchState, "refused")
    compare(store.dispatchError, tc.blockedMessage, "am's sentence, verbatim")
    compare(store.dispatchErrorType, "StoryBlockedError")
    compare(JSON.stringify(store.dispatchSuggest), '{"id":"m1","title":"M3 Document runs"}')
    compare(store.dispatchStart(), false, "Start stays refused")
    var storyLookup = store.dispatchDefaultsRunner.current
    compare(store.retargetToMilestone(), true)
    compare(store.dispatchState, "previewing")
    compare(store.dispatchTarget.level, "milestone")
    compare(JSON.stringify(store.dispatchTarget.flags), JSON.stringify(["--milestone", "m1"]))
    compare(store.dispatchTargetLabel, 'Milestone "M3 Document runs"')
    compare(store.dispatchSuggest, null)
    compare(store.dispatchError, "")
    compare(store.dispatchErrorType, "")
    var lookup = store.dispatchDefaultsRunner.current
    verify(lookup !== storyLookup, "a fresh --defaults lookup")
    compare(argv(lookup), tc.previewCmd + "--defaults|/home/u/my proj")
    reply(lookup, defaultsOk("main"), 0)
    compare(argv(store.dispatchPreviewRunner.current), tc.previewCmd + tc.previewArgs, "the milestone is previewed")
  }

  // 2.1 test 10
  function test_retarget_refused_outside_a_blocked_refusal() {
    var cards = dispatchCards()
    var idle = dispatchStore(); if (!idle) return
    checkRetargetRefused(idle, "idle")
    checkDispatchIdle(idle, "idle after the refusal")

    var ready = readyStore(); if (!ready) return
    checkRetargetRefused(ready, "ready")

    var claimed = storyPreviewingStore(); if (!claimed) return
    reply(claimed.dispatchPreviewRunner.current, ctlFail("ClaimedError", "story s1 is claimed by run r-other"), 0)
    checkRetargetRefused(claimed, "ClaimedError")

    var form = dispatchStore(); if (!form) return
    form.openDispatch("board", cards)
    reply(form.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(form.dispatchErrorType, "Form")
    checkRetargetRefused(form, "Form")

    var target = dispatchStore(); if (!target) return
    var doneCards = dispatchCards()
    doneCards.s1 = { id: "s1", title: "Dispatch store", status: "done", parentId: "m1", depth: 1 }
    target.openDispatch(doneCards.s1, doneCards)
    compare(target.dispatchErrorType, "Target")
    checkRetargetRefused(target, "Target")

    var failed = readyStore(); if (!failed) return
    failed.dispatchStart()
    reply(failed.dispatchStartRunners[0].current, ctlFail("AmExited", "am run exited at once (exit 2)"), 0)
    compare(failed.dispatchState, "failed")
    checkRetargetRefused(failed, "failed")

    var orphan = dispatchStore(); if (!orphan) return
    var orphanCards = dispatchCards()
    orphanCards.o1 = { id: "o1", title: "Orphan", status: "todo", parentId: "", depth: 1 }
    orphan.openDispatch(orphanCards.o1, orphanCards)
    reply(orphan.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(argv(orphan.dispatchPreviewRunner.current),
            tc.previewCmd + "/home/u/my proj|story|o1|--base-branch|main|--branch-prefix|old|--max-concurrent|4|--verify|uv run pytest")
    reply(orphan.dispatchPreviewRunner.current, ctlFail("StoryBlockedError", "story o1 is blocked"), 0)
    compare(orphan.dispatchState, "refused")
    compare(orphan.dispatchErrorType, "StoryBlockedError")
    compare(orphan.dispatchSuggest, null, "no milestone to offer")
    compare(orphan.dispatchTargetLabel, 'Story "Orphan"')
    checkRetargetRefused(orphan, "a blocked story with no milestone")

    var closed = storyPreviewingStore(); if (!closed) return
    reply(closed.dispatchPreviewRunner.current, ctlFail("StoryBlockedError", tc.blockedMessage), 0)
    compare(closed.closeDispatch(), true)
    checkRetargetRefused(closed, "closed after a blocked refusal")
    checkDispatchIdle(closed, "still idle")
  }

  // 2.1 test 13
  function test_an_edit_after_a_blocked_refusal_previews_again() {
    var store = storyPreviewingStore(); if (!store) return
    reply(store.dispatchPreviewRunner.current, ctlFail("StoryBlockedError", tc.blockedMessage), 0)
    compare(store.setDispatchField("prefix", "x"), true)
    compare(store.dispatchState, "previewing")
    compare(store.dispatchSuggest, null)
    compare(store.dispatchError, "")
    compare(store.dispatchErrorType, "")
    checkRetargetRefused(store, "previewing after the edit")
    fire(store.dispatchDebounceTimer)
    compare(argv(store.dispatchPreviewRunner.current),
            tc.previewCmd + "/home/u/my proj|story|s1|--base-branch|main|--branch-prefix|x|--max-concurrent|4|--verify|uv run pytest")
    reply(store.dispatchPreviewRunner.current, ctlFail("StoryBlockedError", tc.blockedMessage), 0)
    compare(store.dispatchState, "refused")
    compare(JSON.stringify(store.dispatchSuggest), '{"id":"m1","title":"M3 Document runs"}', "the action comes back")
  }

  // 2.1 Review Focus 4 and 5
  function test_retarget_goes_once_to_the_milestone_recorded_at_the_opening() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.openDispatch(cards.s1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    store.setDispatchField("parallelism", 2)
    fire(store.dispatchDebounceTimer)
    reply(store.dispatchPreviewRunner.current, ctlFail("StoryBlockedError", tc.blockedMessage), 0)
    cards.m1 = { id: "m1", title: "M4 Renamed", status: "todo", parentId: "", depth: 0 }
    compare(store.retargetToMilestone(), true)
    compare(store.dispatchTargetLabel, 'Milestone "M3 Document runs"', "the milestone recorded at the opening")
    compare(JSON.stringify(store.dispatchTarget.flags), JSON.stringify(["--milestone", "m1"]))
    compare(store.dispatchForm.parallelism, 4, "the story's edits are not carried over")
    compare(store.dispatchForm.prefix, "old")
    checkRetargetRefused(store, "the second call, while previewing")
  }

  // Project A with story s1's preview landed: Start is allowed.
  function storyReadyStore() {
    var store = storyPreviewingStore(); if (!store) return null
    reply(store.dispatchPreviewRunner.current, previewOk(storyDryRun()), 0)
    return store
  }

  // 2.1 test 6
  function test_a_story_start_saves_the_prefix_under_its_milestone() {
    var store = makeWithProject(rootA); if (!store) return
    reply(runsOf(store).runSettingsRunner.current, keyedSettings({ m9: "x" }), 0)
    var cards = dispatchCards()
    store.openDispatch(cards.s1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(store.dispatchPreviewRunner.current, previewOk(storyDryRun()), 0)
    compare(store.dispatchStart(), true)
    var runner = store.dispatchStartRunners[0]
    compare(argv(runner.current), tc.startCmd + tc.storyPreviewArgs)
    reply(runner.current, startOk("r-1", ""), 0)
    compare(store.dispatchState, "started")
    compare(argv(runner.current), tc.viewerCmd + "set-run-settings|/home/u/my proj|" +
            '{"verify":["uv run pytest"],"allowNoVerification":false,"prefixHistory":["old"],"parallelism":4,"prefixByMilestone":{"m1":"old"}}')
    var map = store.runSettings.prefixByMilestone
    compare(Object.keys(map).sort().join(","), "m1,m9", "merged locally")
    compare(map.m9, "x", "the stored entry is kept")
    compare(map.m1, "old")
    compare(store.runSettings.prefixHistory.join(","), "old")
    compare(store.runSettings.confirmDispatch, true, "keys the start does not write are kept")
  }

  // 2.1 test 7
  function test_milestone_starts_key_the_prefix_and_subtask_or_board_starts_do_not() {
    var store = readyStore(); if (!store) return
    store.dispatchStart()
    var runner = store.dispatchStartRunners[0]
    reply(runner.current, startOk("r-1", ""), 0)
    compare(runner.current.command[4], tc.savedJson, "a milestone start keys its own id")
    compare(store.runSettings.prefixByMilestone.m1, "old")

    var plain = '{"verify":["uv run pytest"],"allowNoVerification":false,"prefixHistory":["old"],"parallelism":4}'
    var cards = dispatchCards()
    var subtask = dispatchStore(); if (!subtask) return
    subtask.openDispatch(cards.t1, cards)
    reply(subtask.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(subtask.dispatchStart(), true)
    var subtaskRunner = subtask.dispatchStartRunners[0]
    reply(subtaskRunner.current, startOk("r-2", ""), 0)
    compare(argv(subtaskRunner.current), tc.viewerCmd + "set-run-settings|/home/u/my proj|" + plain, "a subtask start keys nothing")
    compare(subtask.runSettings.prefixByMilestone, undefined, "nothing keyed locally")

    var board = dispatchStore(); if (!board) return
    board.openDispatch("board", cards)
    reply(board.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    board.setDispatchField("prefix", "old")
    fire(board.dispatchDebounceTimer)
    reply(board.dispatchPreviewRunner.current, previewOk({ board: true, levels: [] }), 0)
    compare(board.dispatchState, "ready")
    compare(board.dispatchStart(), true)
    var boardRunner = board.dispatchStartRunners[0]
    reply(boardRunner.current, startOk("r-3", ""), 0)
    compare(argv(boardRunner.current), tc.viewerCmd + "set-run-settings|/home/u/my proj|" + plain, "a board start keys nothing")
  }

  // 2.1 Review Focus 2
  function test_a_stored_map_that_is_not_an_object_merges_from_nothing() {
    var stored = [[], "x", ["a"], 7, null]
    for (var i = 0; i < stored.length; i++) {
      var store = makeWithProject(rootA); if (!store) return
      reply(runsOf(store).runSettingsRunner.current, keyedSettings(stored[i]), 0)
      var cards = dispatchCards()
      store.openDispatch(cards.s1, cards)
      reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
      reply(store.dispatchPreviewRunner.current, previewOk(storyDryRun()), 0)
      store.dispatchStart()
      reply(store.dispatchStartRunners[0].current, startOk("r-1", ""), 0)
      compare(store.dispatchState, "started", "stored " + i)
      compare(Object.keys(store.runSettings.prefixByMilestone).join(","), "m1", "stored " + i + ": only the new entry")
      compare(store.runSettings.prefixByMilestone.m1, "old", "stored " + i)
    }
  }

  // 2.1 Review Focus 3
  function test_the_keyed_prefix_is_the_trimmed_one_sent() {
    var store = storyPreviewingStore(); if (!store) return
    store.setDispatchField("prefix", "  m3-spaced ")
    fire(store.dispatchDebounceTimer)
    reply(store.dispatchPreviewRunner.current, previewOk(storyDryRun()), 0)
    compare(store.dispatchStart(), true)
    var runner = store.dispatchStartRunners[0]
    compare(runner.current.command[8], "m3-spaced", "sent trimmed")
    compare(runner.savedJson, '{"verify":["uv run pytest"],"allowNoVerification":false,"prefixHistory":["m3-spaced","old"],' +
                              '"parallelism":4,"prefixByMilestone":{"m1":"m3-spaced"}}')
    reply(runner.current, startOk("r-1", ""), 0)
    compare(store.runSettings.prefixByMilestone.m1, "m3-spaced")
  }

  // A StoryBlockedError start failure, with the log fields start-run.py adds.
  function startBlocked() {
    return JSON.stringify({ ok: false, error: { type: "StoryBlockedError", message: tc.blockedMessage },
      log: "/home/u/.local/state/am-run.log", pid: 4242, started_at: "2026-10-05T02:14:00Z", exit_code: 2,
      log_tail: "error: story s1 is blocked" }) + "\n"
  }

  // 2.1 test 9
  function test_retarget_from_a_blocked_start() {
    var store = storyReadyStore(); if (!store) return
    var spy = spyC.createObject(tc, { target: store, signalName: "dispatchStarted" })
    var settingsBefore = JSON.stringify(store.runSettings)
    compare(store.dispatchStart(), true)
    var seq = runsOf(store).snapshotRunner.seq
    reply(store.dispatchStartRunners[0].current, startBlocked(), 0)
    compare(store.dispatchState, "refused", "a blocked story is refused, not failed")
    compare(store.dispatchError, tc.blockedMessage)
    compare(store.dispatchErrorType, "StoryBlockedError")
    compare(store.dispatchLog, "")
    compare(store.dispatchLogTail, "")
    compare(store.dispatchExitCode, null)
    compare(JSON.stringify(store.dispatchSuggest), '{"id":"m1","title":"M3 Document runs"}')
    compare(store.dispatchStartRunners.length, 0, "the runner is dropped: no set-run-settings")
    compare(JSON.stringify(store.runSettings), settingsBefore, "nothing saved")
    compare(store.dispatchForm.prefix, "old", "the form stays")
    compare(spy.count, 0)
    compare(runsOf(store).snapshotRunner.seq, seq, "no re-snapshot")
    compare(store.dispatchStart(), false, "Start stays refused")
    compare(store.retargetToMilestone(), true)
    compare(store.dispatchState, "previewing")
    compare(store.dispatchTarget.level, "milestone")
    compare(JSON.stringify(store.dispatchTarget.flags), JSON.stringify(["--milestone", "m1"]))
    compare(store.dispatchTargetLabel, 'Milestone "M3 Document runs"')
    compare(store.dispatchSuggest, null)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(argv(store.dispatchPreviewRunner.current), tc.previewCmd + tc.previewArgs)

    var blank = storyReadyStore(); if (!blank) return
    blank.dispatchStart()
    reply(blank.dispatchStartRunners[0].current, ctlFail("StoryBlockedError", "  "), 0)
    compare(blank.dispatchState, "refused")
    compare(blank.dispatchError, "The launch could not be read")
    compare(blank.dispatchErrorType, "StoryBlockedError")
    compare(JSON.stringify(blank.dispatchSuggest), '{"id":"m1","title":"M3 Document runs"}')
  }

  // 2.1 test 11 (the start half)
  function test_a_claimed_story_start_fails_with_the_log() {
    var store = storyReadyStore(); if (!store) return
    store.dispatchStart()
    reply(store.dispatchStartRunners[0].current, JSON.stringify({ ok: false,
      error: { type: "ClaimedError", message: "story s1 is claimed by run r-other" },
      log: "/home/u/.local/state/am-run.log", exit_code: 1, log_tail: "claimed" }) + "\n", 0)
    compare(store.dispatchState, "failed")
    compare(store.dispatchError, "story s1 is claimed by run r-other")
    compare(store.dispatchErrorType, "ClaimedError")
    compare(store.dispatchLog, "/home/u/.local/state/am-run.log")
    compare(store.dispatchLogTail, "claimed")
    compare(store.dispatchExitCode, 1)
    compare(store.dispatchSuggest, null)
    compare(store.retargetToMilestone(), false)
  }

  // 2.1 Review Focus 1
  function test_a_late_blocked_start_reply_changes_nothing() {
    var store = storyReadyStore(); if (!store) return
    store.dispatchStart()
    var proc = store.dispatchStartRunners[0].current
    runsOf(store).project = rootB
    checkDispatchIdle(store, "B after the switch")
    reply(proc, startBlocked(), 0)
    checkDispatchIdle(store, "B after A's blocked reply")
    compare(store.dispatchStartRunners.length, 0, "the runner goes")

    var back = storyReadyStore(); if (!back) return
    back.dispatchStart()
    var backProc = back.dispatchStartRunners[0].current
    runsOf(back).project = rootB
    runsOf(back).project = rootA
    reply(runsOf(back).runSettingsRunner.current, dispatchSettings(), 0)
    var cards = dispatchCards()
    compare(back.openDispatch(cards.m1, cards), true)
    reply(backProc, startBlocked(), 0)
    compare(back.dispatchState, "previewing", "the new dialog is not overwritten")
    compare(back.dispatchError, "")
    compare(back.dispatchErrorType, "")
    compare(back.dispatchSuggest, null)
    compare(back.dispatchTargetLabel, 'Milestone "M3 Document runs"')
  }
}
