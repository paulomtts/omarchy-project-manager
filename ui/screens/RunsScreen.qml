import QtQuick
import qs.Commons
import qs.Ui
import "../../core/domain/runs.js" as Runs
import "../components/runGlyphs.js" as RunGlyphs
import "../components/runControlFacts.js" as ControlFacts
import "../components" as UI
import "../theme" as T

// The Runs section: every registered project's am runs, grouped by project
// with a header each (name; live, parked and needs-attention counts; the
// project's snapshot error), flat with no header under a project filter. Each
// run is one row (state glyph; title, from the run's own project's map in
// app.runTitles; short id in dim; done/total, current phase, age) whose index
// is its position in the store's filteredRuns, the one list
// the cursor walks; headers are not cursor targets. A project chip row (All
// projects, This project when one is open, one chip per project with runs,
// with run counts) sits above the status chips, hidden when only one project
// has runs and none is open; clicking one asks the store to toggle its
// project filter. Needs attention / Live / Parked / All chips apply across
// groups and count within the project filter -- clicking the active chip
// means All again -- and a footer says whether the runs are watched. The row
// with the cursor shows Open project for a run of a registered project other
// than the open one; the button asks the navigator to choose that project. It
// reads the run store, the run titles and the project registry and asks the
// navigator to open a run, choose a project or move the cursor; it owns no
// state of its own.
// Ages are read against the clock once per snapshot: there is no timer.
Column {
  id: screen
  objectName: "runsView"

  property var app
  property var navigator
  property var theme: T.Theme {}

  // The panel scrolls; a row that takes the cursor asks for it here.
  signal revealRequested(var item)
  // A run's Cancel was clicked. Cancelling needs a typed confirmation, which is
  // the owner's to ask for; nothing here cancels a run.
  signal cancelRequested(string runId)

  // Re-read whenever the list changes, i.e. with every snapshot.
  readonly property real nowMs: screen.app.runs.filteredRuns ? Date.now() : 0
  readonly property bool amMissing: screen.app.runs.amStatus === "missing"
  // The status chips' counts: the project filter's runs, whatever the search.
  readonly property var counts: Runs.runFilterCounts(Runs.filterByProject(screen.app.runs.runs, screen.app.runs.projectFilter))
  // The registry is empty: the status line says so whatever the chip or the
  // search.
  readonly property bool noProjects: screen.sizeOf(screen.app.runs.projectRoots) === 0
  // The open project's root, by rootKey; "" when none is open.
  readonly property string openRoot: screen.rootKey(screen.app.runs.project)
  // Every listed run by project, whatever the status chip, the search or the
  // project filter: the project chips are counted from these.
  readonly property var allGroups: Runs.groupByProject(screen.app.runs.runs)
  // How many projects have runs.
  readonly property int projectsWithRuns: screen.projectsIn(screen.allGroups)
  // The project chip row's model (projectChipsOf).
  readonly property var projectChips: screen.projectChipsOf(screen.allGroups, screen.openRoot)

  // What the list draws, in order (entriesOf).
  readonly property var entries: screen.entriesOf(screen.app.runs.groups, screen.app.runs.filteredRuns,
    screen.app.runs.projectRoots, screen.app.runs.projectErrors, screen.app.runs.projectFilter)

  visible: screen.app.nav.viewMode === "runs"
  spacing: Style.space(6)

  // A chip's wording, also used by the "No <chip> runs." line.
  function chipLabel(id) {
    return id === "attention" ? "Needs attention" : id === "live" ? "Live" : id === "parked" ? "Parked" : "All"
  }

  // The length of a list or array-like object; 0 for anything else.
  function sizeOf(list) {
    return list !== null && typeof list === "object" && typeof list.length === "number" ? list.length : 0
  }

  // A group's counts: the non-zero parts of "<n> live", "<n> parked" and
  // "<n> needs attention", in that order, joined by " · "; "" when all are zero.
  function countsText(counts) {
    var c = counts !== null && typeof counts === "object" ? counts : {}
    var parts = []
    if (c.live > 0) parts.push(c.live + " live")
    if (c.parked > 0) parts.push(c.parked + " parked")
    if (c.attention > 0) parts.push(c.attention + " needs attention")
    return parts.join(" · ")
  }

  // A root as the store compares roots: every trailing "/" removed, "/" for a
  // root of only slashes, "" for a non-string.
  function rootKey(path) {
    if (typeof path !== "string") return ""
    var end = path.length
    while (end > 0 && path.charAt(end - 1) === "/") end--
    if (end === 0) return path === "" ? "" : "/"
    return path.substring(0, end)
  }

  // The snapshot error `errors` ({root: sentence}) holds for `root`, keys and
  // root compared by rootKey; "" when there is none, when `root` is "", or
  // when the sentence is not a string.
  function projectError(errors, root) {
    var want = screen.rootKey(root)
    if (want === "" || errors === null || typeof errors !== "object") return ""
    var keys = Object.keys(errors)
    for (var k = 0; k < keys.length; k++) {
      if (screen.rootKey(keys[k]) === want && typeof errors[keys[k]] === "string") return errors[keys[k]]
    }
    return ""
  }

  // How many groups of `groups` have a root other than "".
  function projectsIn(groups) {
    var n = 0
    for (var g = 0; g < screen.sizeOf(groups); g++) {
      if (groups[g].project.root !== "") n++
    }
    return n
  }

  // The project chips, scalar values only (a Repeater converts nested ones):
  // All projects (id "all", no count); This project (id "this") when `open`
  // is not "", counting the runs of `open`'s group, 0 when it has none; then
  // one chip per group of `groups` (groupByProject output), in order, except
  // the root "" group and `open`'s: id its root, label its name else its
  // root, count its runs.
  function projectChipsOf(groups, open) {
    var tint = screen.theme.dim
    var named = []
    var openCount = 0
    for (var g = 0; g < screen.sizeOf(groups); g++) {
      var group = groups[g]
      var root = group.project.root
      if (root === "") continue
      if (root === open) {
        openCount = screen.sizeOf(group.runs)
        continue
      }
      named.push({ id: root, label: group.project.name !== "" ? group.project.name : root,
                   count: screen.sizeOf(group.runs), tint: tint })
    }
    var out = [{ id: "all", label: "All projects", tint: tint }]
    if (open !== "") out.push({ id: "this", label: "This project", count: openCount, tint: tint })
    return out.concat(named)
  }

  // The project chip `filter` (the store's projectFilter) makes active: "all"
  // for "", "this" when it is `open`, else its root, which no chip has when
  // that project has no chip.
  function activeProjectChipOf(filter, open) {
    var key = screen.rootKey(filter)
    return key === "" ? "all" : key === open ? "this" : key
  }

  // A project chip was clicked: the store toggles its project filter with ""
  // for All projects, the open project for This project, else the chip's root.
  function chooseProject(id) {
    screen.app.runs.toggleProjectFilter(id === "all" ? "" : id === "this" ? screen.app.runs.project : id)
  }

  // The first entry of the registry `list` ({root_path, name} objects, in
  // list order) whose root_path is `root`, both compared by rootKey; null
  // when `root` is "", `list` is not array-like or no entry matches. Entries
  // that are not objects are skipped.
  function registryEntryOf(list, root) {
    var want = screen.rootKey(root)
    if (want === "") return null
    for (var i = 0; i < screen.sizeOf(list); i++) {
      var entry = list[i]
      if (entry !== null && typeof entry === "object" && screen.rootKey(entry.root_path) === want) return entry
    }
    return null
  }

  // The registry entry Open project chooses for `run`: registryEntryOf
  // `list` for the run's project.root; null when the run has no project or
  // its project's root is `open` (the open project's, by rootKey).
  function openProjectTargetOf(run, open, list) {
    var project = run !== null && typeof run === "object" ? run.project : null
    var root = screen.rootKey(project !== null && typeof project === "object" ? project.root : "")
    return root === "" || root === open ? null : screen.registryEntryOf(list, root)
  }

  // The list's entries, scalar values only (a Repeater converts nested ones):
  // { kind: "header", g, name, counts, error }, { kind: "run", i } with i the
  // run's index in `runs` (filteredRuns, which is displayOrder of `groups`),
  // and { kind: "projectError", text }.
  // Under a project filter: the filtered project's error when it has one,
  // then every run, flat. Otherwise each group of `groups` in turn: a header
  // unless its root is "", then its runs; then, for each root of the registry
  // `roots` (in order, once) with an error and no group, a header with no
  // counts and no runs. g counts the headers from 0; name is the project's
  // name, else its root; error is projectError's.
  function entriesOf(groups, runs, roots, errors, filter) {
    var out = []
    if (typeof filter === "string" && filter !== "") {
      var flatError = screen.projectError(errors, filter)
      if (flatError !== "") out.push({ kind: "projectError", text: flatError })
      for (var r = 0; r < screen.sizeOf(runs); r++) out.push({ kind: "run", i: r })
      return out
    }
    var listed = Object.create(null)
    var g = 0
    var i = 0
    for (var n = 0; n < screen.sizeOf(groups); n++) {
      var group = groups[n]
      var root = group.project.root
      if (root !== "") {
        listed[root] = true
        out.push({ kind: "header", g: g++, name: group.project.name !== "" ? group.project.name : root,
                   counts: screen.countsText(group.counts), error: screen.projectError(errors, root) })
      }
      for (var j = 0; j < screen.sizeOf(group.runs); j++) out.push({ kind: "run", i: i++ })
    }
    for (var e = 0; e < screen.sizeOf(roots); e++) {
      var project = roots[e]
      if (project === null || typeof project !== "object") continue
      var key = screen.rootKey(project.root)
      if (key === "" || listed[key]) continue
      var error = screen.projectError(errors, key)
      if (error === "") continue
      listed[key] = true
      out.push({ kind: "header", g: g++, name: typeof project.name === "string" && project.name !== "" ? project.name : key,
                 counts: "", error: error })
    }
    return out
  }

  // A dead or parked run's state, spelled out with its age folded in so the
  // age shows once; "" for every other state.
  function stateText(state, age) {
    if (state === "dead")
      return age === "" ? "dead - lease lost" : age === "just now" ? "dead - lease lost just now" : "dead - lease lost " + age + " ago"
    if (state === "parked") return age === "" ? "parked" : "parked " + age
    return ""
  }

  // A row's control button: pause and resume go straight to the store, a
  // cancel only asks (cancelRequested).
  function requestControl(action, run) {
    var id = ControlFacts.runIdOf(run)
    if (id === "") return
    if (action === "cancel") screen.cancelRequested(id)
    else screen.app.runControl.control(action, id)
  }

  UI.ThemedText {
    objectName: "runsSchemaBanner"
    theme: screen.theme
    width: parent.width
    visible: !screen.amMissing && screen.app.runs.amStatus === "schema"
    text: screen.app.runs.watchSchemaError !== "" ? screen.app.runs.watchSchemaError : screen.app.runs.lastError
    color: screen.theme.urgent
    wrapMode: Text.WordWrap
  }

  UI.ThemedText {
    objectName: "runsStaleBanner"
    theme: screen.theme
    width: parent.width
    visible: !screen.amMissing && screen.app.runs.stale
    text: "Run data is out of date"
    color: screen.theme.urgent
  }

  UI.ThemedText {
    objectName: "runsWarning"
    variant: "caption"
    theme: screen.theme
    width: parent.width
    visible: !screen.amMissing && screen.app.runs.watchWarning !== ""
    text: screen.app.runs.watchWarning
    elide: Text.ElideRight
  }

  // Shown while a project is open or more than one project has runs.
  UI.ChipRow {
    objectName: "runProjectChips"
    width: parent.width
    theme: screen.theme
    chipPrefix: "runProjectChip"
    visible: !screen.amMissing && (screen.openRoot !== "" || screen.projectsWithRuns > 1)
    model: screen.projectChips
    active: screen.activeProjectChipOf(screen.app.runs.projectFilter, screen.openRoot)
    onChosen: function(id) { screen.chooseProject(id) }
  }

  UI.FilterableList {
    width: parent.width
    theme: screen.theme

    chipsObjectName: "runChips"
    chipPrefix: "runChip"
    statusObjectName: "runsMessage"
    chips: ["attention", "live", "parked", "all"].map(function(id) {
      var chip = { id: id, label: screen.chipLabel(id), tint: screen.theme.dim }
      if (id !== "all") chip.count = screen.counts[id]
      return chip
    })
    activeChip: screen.app.runs.runFilter === "" ? "all" : screen.app.runs.runFilter
    onChipToggled: function(id) { screen.app.runs.toggleRunFilter(id) }

    error: screen.amMissing ? "am is not installed or not on PATH" : ""
    empty: screen.app.runs.filteredRuns.length === 0
    filtered: !screen.noProjects && (screen.app.nav.searchQuery !== "" || screen.app.runs.runFilter !== "")
    filteredText: screen.app.nav.searchQuery !== ""
      ? "No runs match “" + screen.app.nav.searchQuery + "”."
      : "No " + screen.chipLabel(screen.app.runs.runFilter) + " runs."
    emptyText: screen.noProjects ? "No projects registered." : "No runs yet."

    model: screen.entries
    rowDelegate: Component { RunEntry {} }
  }

  // The global Notify on escalation setting: a desktop notification for
  // every run toast. Shown with or without a project, and while am is missing.
  Row {
    objectName: "runsNotifyRow"
    spacing: Style.space(8)

    ToggleSwitch {
      objectName: "runsNotifyToggle"
      anchors.verticalCenter: parent.verticalCenter
      checked: screen.app.runControl.notifyOnEscalation
      onToggled: screen.app.runControl.setNotifyOnEscalation(!screen.app.runControl.notifyOnEscalation)
    }

    UI.ThemedText {
      objectName: "runsNotifyLabel"
      anchors.verticalCenter: parent.verticalCenter
      variant: "caption"
      theme: screen.theme
      text: "Notify on escalation"
    }
  }

  // The watch line, naming the am version and journal schema the watch
  // announced once they are known, or why the last run key was refused while
  // that flash lasts; a flash shows even where the footer is otherwise hidden.
  UI.ThemedText {
    objectName: "runsFooter"
    variant: "caption"
    theme: screen.theme
    width: parent.width
    visible: (!screen.amMissing && screen.app.runs.amStatus !== "schema") || screen.app.runControl.flashText !== ""
    text: screen.app.runControl.flashText !== ""
      ? screen.app.runControl.flashText
      : screen.app.runs.amStatus === "error" && screen.app.runs.lastError !== ""
        ? screen.app.runs.lastError
        : "am" +
          (screen.app.runs.amSchema > 0 && screen.app.runs.amVersion !== "" ? " " + screen.app.runs.amVersion : "") +
          (screen.app.runs.amSchema > 0 ? " · schema " + screen.app.runs.amSchema : "") +
          " · " + (screen.app.runs.watching ? "watching" : "not watching")
    wrapMode: Text.WordWrap
  }

  // One entry of `entries`: a project's header, a run's row or the filtered
  // project's error line.
  component RunEntry: Loader {
    id: entry
    required property var modelData
    readonly property var fact: entry.modelData !== null && typeof entry.modelData === "object" ? entry.modelData : ({})

    width: screen.width
    sourceComponent: entry.fact.kind === "header" ? headerC
      : entry.fact.kind === "run" ? rowC
      : entry.fact.kind === "projectError" ? projectErrorC
      : null

    Component {
      id: headerC
      RunGroupHeader {
        g: typeof entry.fact.g === "number" ? entry.fact.g : 0
        name: typeof entry.fact.name === "string" ? entry.fact.name : ""
        counts: typeof entry.fact.counts === "string" ? entry.fact.counts : ""
        error: typeof entry.fact.error === "string" ? entry.fact.error : ""
      }
    }

    Component {
      id: rowC
      RunRow { index: typeof entry.fact.i === "number" ? entry.fact.i : -1 }
    }

    // The filtered project's snapshot error, above its runs.
    Component {
      id: projectErrorC
      UI.ThemedText {
        objectName: "runsProjectError"
        variant: "caption"
        theme: screen.theme
        width: screen.width
        text: typeof entry.fact.text === "string" ? entry.fact.text : ""
        color: screen.theme.urgent
        wrapMode: Text.WordWrap
      }
    }
  }

  // A project's header: its name, its counts and, when its snapshot failed,
  // the error. Not a row: no cursor, no hover, no click.
  component RunGroupHeader: Column {
    id: header
    property int g: 0
    property string name: ""
    property string counts: ""
    property string error: ""
    readonly property real innerWidth: Math.max(0, header.width - header.leftPadding - header.rightPadding)

    objectName: "runGroup" + header.g
    width: screen.width
    leftPadding: Style.space(10)
    rightPadding: Style.space(10)
    topPadding: Style.space(4)
    spacing: Style.space(2)

    Row {
      width: header.innerWidth
      spacing: Style.space(8)

      UI.ThemedText {
        objectName: "runGroupName" + header.g
        theme: screen.theme
        font.bold: true
        width: Math.max(0, Math.min(implicitWidth,
          parent.width - (groupCounts.visible ? groupCounts.width + parent.spacing : 0)))
        text: header.name
        elide: Text.ElideRight
      }

      UI.ThemedText {
        id: groupCounts
        objectName: "runGroupCounts" + header.g
        variant: "caption"
        theme: screen.theme
        visible: text !== ""
        text: header.counts
      }
    }

    UI.ThemedText {
      objectName: "runGroupError" + header.g
      variant: "caption"
      theme: screen.theme
      width: header.innerWidth
      visible: text !== ""
      text: header.error
      color: screen.theme.urgent
      wrapMode: Text.WordWrap
    }
  }

  // A run's row; `index` is the run's position in filteredRuns.
  component RunRow: UI.ListRow {
    id: row
    objectName: "runRow" + row.index

    // The run is read back out of the store's list by position, NOT taken from
    // `modelData`: a Repeater hands the delegate a converted copy whose nested
    // arrays are no longer JS arrays (Array.isArray is false), so the domain
    // helpers that read `tree.subtasks` and `rows` would see an empty run and
    // the progress, phase and escalation reason would silently vanish.
    readonly property var run: screen.app.runs.filteredRuns[row.index]

    // The registry entry Open project chooses (openProjectTargetOf); null
    // hides the button.
    readonly property var openTarget: screen.openProjectTargetOf(row.run, screen.openRoot, screen.app.projects.projects)

    readonly property string runState: Runs.runState(row.run)
    readonly property var runProgress: Runs.runProgress(row.run)
    readonly property string runAge: Runs.runAgeText(row.run, screen.nowMs)

    width: screen.width
    theme: screen.theme
    opacity: screen.app.runs.stale ? 0.5 : 1
    cursorIndex: screen.app.nav.cursorIndex
    scrollOnCursor: screen.app.nav.scrollOnCursor
    onHovered: function(index) { screen.navigator.hoverCursor(index) }
    onActivated: screen.navigator.openRun(row.run ? row.run.id : "")
    onRevealRequested: function(item) { screen.revealRequested(item) }

    Row {
      width: parent.width
      spacing: Style.space(8)

      UI.ThemedText {
        id: rowGlyph
        objectName: "runRowGlyph" + row.index
        theme: screen.theme
        visible: text !== ""
        text: RunGlyphs.glyphOf(row.runState)
        color: row.runState === "escalated" || row.runState === "dead" ? screen.theme.urgent : screen.theme.foreground
      }

      UI.ThemedText {
        objectName: "runRowTitle" + row.index
        theme: screen.theme
        width: Math.max(0, parent.width - (rowGlyph.visible ? rowGlyph.width + parent.spacing : 0)
          - rowId.width - parent.spacing)
        text: Runs.runTitle(row.run, Runs.titlesOfRun(row.run, screen.app.runTitles.titlesByRoot))
        elide: Text.ElideRight
      }

      UI.ThemedText {
        id: rowId
        objectName: "runRowId" + row.index
        variant: "caption"
        theme: screen.theme
        text: Runs.runSubtitle(row.run)
        color: screen.theme.dim
      }
    }

    Row {
      width: parent.width
      spacing: Style.space(10)

      UI.ThemedText {
        objectName: "runRowProgress" + row.index
        variant: "caption"
        theme: screen.theme
        visible: text !== ""
        text: row.runProgress.total > 0 ? row.runProgress.done + "/" + row.runProgress.total : ""
      }

      UI.ThemedText {
        objectName: "runRowPhase" + row.index
        variant: "caption"
        theme: screen.theme
        visible: text !== ""
        text: Runs.currentPhase(row.run)
      }

      UI.ThemedText {
        objectName: "runRowAge" + row.index
        variant: "caption"
        theme: screen.theme
        visible: text !== ""
        text: row.runState === "dead" || row.runState === "parked" ? "" : row.runAge
      }

      UI.ThemedText {
        objectName: "runRowState" + row.index
        variant: "caption"
        theme: screen.theme
        visible: text !== ""
        text: screen.stateText(row.runState, row.runAge)
        color: row.runState === "dead" ? screen.theme.urgent : screen.theme.dim
      }
    }

    UI.ThemedText {
      objectName: "runRowReason" + row.index
      variant: "caption"
      theme: screen.theme
      width: parent.width
      visible: row.runState === "escalated"
      text: Runs.escalationReason(row.run)
      color: screen.theme.urgent
      wrapMode: Text.WordWrap
    }

    // Under the row: the buttons while it has the cursor (hover moves the
    // cursor, so that is hover or selected) or a request is pending, and the
    // waiting and error lines whenever they apply; then Open project while it
    // has the cursor and openTarget is not null.
    actions: [
      UI.RunControls {
        objectName: "runRowControls" + row.index
        width: parent.width
        theme: screen.theme
        run: row.run
        pendingAction: ControlFacts.pendingOf(screen.app.runControl.pending, row.run)
        waiting: ControlFacts.waitingOf(screen.app.runControl.stillWaiting, row.run)
        waitingText: screen.app.runControl.stillWaitingText
        errorText: ControlFacts.errorOf(screen.app.runControl.lastControlError, screen.app.runControl.lastControlErrorRunId, row.run)
        wholeRun: false
        showButtons: row.hasCursor
        onActionRequested: function(action) { screen.requestControl(action, row.run) }
      },
      UI.ActionButton {
        objectName: "runRowOpenProject" + row.index
        theme: screen.theme
        text: "Open project"
        visible: row.hasCursor && row.openTarget !== null
        onClicked: screen.navigator.chooseProject(row.openTarget)
      }
    ]
  }
}
