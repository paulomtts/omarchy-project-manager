// tests/ui/screens/tst_runs_screen.qml
// ui/screens/RunsScreen.qml on its own: the rows it renders, the chips, the
// footer and banners, and the empty and missing states. A stub app: a REAL
// NavigationStore, plus plain objects carrying the RunStore properties and,
// apart, the RunControlStore and RunTitlesStore properties the screen reads (the real store's
// `watching` is a read-only alias that cannot be set from a test); the run
// list is filtered through the same domain functions the store uses. The
// navigator is a recorder.
import QtQuick
import QtTest
import "../../helpers/find.js" as H
import "../../../core/domain/runs.js" as Runs
import "../../../ui/components/runGlyphs.js" as RG

TestCase {
  id: tc
  name: "RunsScreen"
  when: windowShown
  visible: true
  width: 500; height: 700

  readonly property int minute: 60000

  Component { id: hostC; Item { width: 500; height: 700 } }

  Component {
    id: runsC
    QtObject {
      id: rs
      property var runs: []
      property string runFilter: ""
      property string searchQuery: ""
      property string selectedRunId: ""
      property string amStatus: "ok"
      property string lastError: ""
      property bool stale: false
      property string watchWarning: ""
      property bool watching: true
      property string watchSchemaError: ""
      // The current watch's hello, with the real store's defaults (0 / "" =
      // no hello known).
      property int amSchema: 0
      property string amVersion: ""
      // The registry, the per-root snapshot errors and the project filter, as
      // the real store holds them; groups and filteredRuns derive exactly as
      // the store's do.
      property var projectRoots: [{ root: "/home/u/a", name: "alpha" }]
      property var projectErrors: ({})
      property string projectFilter: ""
      readonly property var groups: Runs.groupByProject(Runs.filterByProject(Runs.searchRuns(Runs.filterRuns(rs.runs, rs.runFilter), rs.searchQuery), rs.projectFilter))
      readonly property var filteredRuns: Runs.displayOrder(rs.groups)
      function toggleRunFilter(id) { rs.runFilter = id === "all" || id === rs.runFilter ? "" : id }
      // The open project's root ("" = none) and the project filter's toggle,
      // as the real store has them: toggleProjectFilter records its argument;
      // "", or the active root again, means All; a root no run has means All.
      // A `var`, not a `string`: a test assigns undefined and a number.
      property var project: ""
      property var projectToggles: []
      function toggleProjectFilter(root) {
        rs.projectToggles = rs.projectToggles.concat([root])
        var want = typeof root === "string" ? root.replace(/\/+$/, "") : ""
        var next = want === "" || want === rs.projectFilter ? "" : want
        rs.projectFilter = rs.hasRoot(next) ? next : ""
      }
      // Some run in `runs` has `root` as its project.root.
      function hasRoot(root) {
        if (root === "") return false
        for (var i = 0; i < rs.runs.length; i++) {
          var p = rs.runs[i] && rs.runs[i].project
          if (p && p.root === root) return true
        }
        return false
      }
      // The store's keepProjectFilter: a filter no run has any more is All.
      onRunsChanged: if (rs.projectFilter !== "" && !rs.hasRoot(rs.projectFilter)) rs.projectFilter = ""
    }
  }

  Component {
    id: controlC
    QtObject {
      id: rc
      property string flashText: ""
      // The control surface the rows read (S2 4.2). `control` only records.
      property var pending: ({})
      property var stillWaiting: ({})
      readonly property string stillWaitingText: "still waiting — the run may be between phases or dead"
      property string lastControlError: ""
      property string lastControlErrorRunId: ""
      property var controlCalls: []
      function control(action, id) {
        rc.controlCalls = rc.controlCalls.concat([action + "|" + id])
        return true
      }
      // The Notify on escalation switch (S2 4.4). `setNotifyOnEscalation`
      // only records.
      property bool notifyOnEscalation: false
      property var notifyCalls: []
      function setNotifyOnEscalation(on) {
        rc.notifyCalls = rc.notifyCalls.concat([on])
        return true
      }
    }
  }

  // The run titles store's surface: the {root: {id: title}} maps, the
  // {root: status} statuses and refreshTitles(), which only counts.
  Component {
    id: titlesC
    QtObject {
      id: ts
      property var titlesByRoot: ({})
      property var titleStatus: ({})
      property int refreshCalls: 0
      function refreshTitles() { ts.refreshCalls += 1 }
    }
  }

  Component {
    id: appC
    QtObject {
      property var nav: null
      property var runs: null
      property var runControl: null
      property var runTitles: null
      // The project registry, as ProjectStore holds it: alpha and beta. A test
      // that changes it assigns a whole new object, so bindings follow.
      property var projects: ({ selectedProject: { root_path: "/home/u/a", name: "alpha" },
                                projects: [{ root_path: "/home/u/a", name: "alpha" },
                                           { root_path: "/home/u/b", name: "beta" }] })
    }
  }

  Component {
    id: naviC
    QtObject {
      property string opened: ""
      property int hovered: -1
      // Every project chooseProject was given, in order.
      property var chosen: []
      function openRun(id) { opened = String(id) }
      function hoverCursor(index) { hovered = index }
      function chooseProject(p) { chosen = chosen.concat([p]) }
    }
  }

  function make(list) {
    var host = createTemporaryObject(hostC, tc)
    var navComp = Qt.createComponent("../../../core/stores/NavigationStore.qml")
    if (navComp.status !== Component.Ready) { fail(navComp.errorString()); return null }
    var nav = navComp.createObject(host)
    var runs = runsC.createObject(host)
    runs.searchQuery = Qt.binding(function() { return nav.searchQuery })
    var control = controlC.createObject(host)
    var titles = titlesC.createObject(host)
    var app = appC.createObject(host, { nav: nav, runs: runs, runControl: control, runTitles: titles })
    var navi = naviC.createObject(host)
    var sC = Qt.createComponent("../../../ui/screens/RunsScreen.qml")
    if (sC.status !== Component.Ready) { fail(sC.errorString()); return null }
    var screen = sC.createObject(host, { width: 500, app: app, navigator: navi })
    nav.viewMode = "runs"
    runs.runs = list || []
    wait(20)
    return { app: app, runs: runs, control: control, titles: titles, nav: nav, navi: navi, screen: screen }
  }

  function ago(ms) { return new Date(Date.now() - ms).toISOString() }

  // Two clicks inside the double-click interval (400 ms) make the second one a
  // double-click, which a MouseArea does not report as `clicked`. Every click in
  // this file goes through here so a test may click more than once.
  function tap(item) {
    wait(450)
    mouseClick(item)
  }

  // A normalised run, as RunStore holds them. live === null means no lease.
  function run(id, status, live, opts) {
    var o = opts || {}
    return { id: id, repo_dir: "/home/u/a", milestone_id: o.milestone === undefined ? "" : o.milestone,
             status: status, started_at: o.started_at || "",
             lease: live === null ? null : { pid: 1, host: "h", heartbeat_at: o.heartbeat_at || "", accepting: true, live: live },
             rows: [], tree: o.tree || { stories: [], subtasks: [] } }
  }

  // 0 running, 1 escalated, 2 dead, 3 parked, 4 cancelled (nothing but an id), 5 done.
  // `r` as the store holds it: tagged with the registered project at `root`.
  function tagged(r, root, name) { return Runs.withProject(r, root, name) }

  // The item exists and is visible.
  function shown(s, name) {
    var item = H.find(s.screen, name)
    return !!item && item.visible
  }

  // An item's top edge in the screen's coordinates.
  function topOf(s, name) { return H.find(s.screen, name).mapToItem(s.screen, 0, 0).y }

  // The project chip row's chip ids, in model order, joined by ",".
  function projectChipIds(s) {
    var model = H.find(s.screen, "runProjectChips").model
    var ids = []
    for (var i = 0; i < model.length; i++) ids.push(model[i].id)
    return ids.join(",")
  }

  // A project chip's text; null when there is no such chip.
  function projectChipText(s, id) {
    var chip = H.find(s.screen, "runProjectChip" + id)
    return chip ? chip.text : null
  }

  // Project A (/home/u/a, "alpha") with an escalated and a dead run, project
  // B (/home/u/b, "beta") with one live run. Display order: A (attention)
  // then B (live), so filteredRuns is escl0001, dead0002, live0003.
  function twoProjects() {
    return [tagged(run("run-a-escl0001", "escalated", null, {}), "/home/u/a", "alpha"),
            tagged(run("run-b-live0003", "started", true, { milestone: "zeta" }), "/home/u/b", "beta"),
            tagged(run("run-a-dead0002", "started", false, {}), "/home/u/a", "alpha")]
  }

  function sample() {
    return [
      run("run-20261004-live0001", "started", true, { milestone: "alpha", started_at: ago(5 * tc.minute), tree: { stories: [], subtasks: [
        { card_id: "t1", status: "done", phases: [{ name: "spec", status: "done" }] },
        { card_id: "t2", status: "started", phases: [{ name: "spec", status: "done" }, { name: "implement", status: "started" }] }] } }),
      run("run-20261004-escl0002", "escalated", null, { milestone: "beta", tree: { stories: [], subtasks: [
        { card_id: "t3", status: "escalated", phases: [{ name: "review", status: "failed", detail: "tests red after 3 attempts" }] }] } }),
      run("run-20261004-dead0003", "started", false, { milestone: "gamma", started_at: ago(180 * tc.minute),
                                                       heartbeat_at: ago(7 * tc.minute) }),
      run("run-20261004-park0004", "stopped", null, { milestone: "delta", started_at: ago(120 * tc.minute) }),
      run("run-20261004-canc0005", "cancelled", null, {}),
      run("run-20261004-done0006", "done", null, { milestone: "epsilon" })
    ]
  }

  // ---- rows

  function test_each_state_shows_its_glyph() {
    var s = make(sample()); if (!s) return
    var states = ["running", "escalated", "dead", "parked", "cancelled", "done"]
    for (var i = 0; i < states.length; i++) {
      var glyph = H.find(s.screen, "runRowGlyph" + i)
      verify(glyph, "row " + i)
      compare(String(glyph.text), RG.glyphOf(states[i]), states[i])
      compare(glyph.visible, true, states[i])
    }
  }

  // Escalated and dead runs are the ones that need attention: their glyph, the
  // dead line and the escalation reason are drawn in `urgent`.
  function test_runs_that_need_attention_are_drawn_urgent() {
    var s = make(sample()); if (!s) return
    var urgent = s.screen.theme.urgent
    verify(!Qt.colorEqual(urgent, s.screen.theme.foreground), "the theme tells urgent from foreground")
    verify(Qt.colorEqual(H.find(s.screen, "runRowGlyph1").color, urgent), "escalated glyph")
    verify(Qt.colorEqual(H.find(s.screen, "runRowGlyph2").color, urgent), "dead glyph")
    verify(Qt.colorEqual(H.find(s.screen, "runRowGlyph0").color, s.screen.theme.foreground), "running glyph")
    verify(Qt.colorEqual(H.find(s.screen, "runRowGlyph3").color, s.screen.theme.foreground), "parked glyph")
    verify(Qt.colorEqual(H.find(s.screen, "runRowState2").color, urgent), "the dead line")
    verify(!Qt.colorEqual(H.find(s.screen, "runRowState3").color, urgent), "the parked line is not urgent")
    verify(Qt.colorEqual(H.find(s.screen, "runRowReason1").color, urgent), "the escalation reason")
  }

  function test_a_row_shows_short_id_title_progress_phase_and_age() {
    var s = make(sample()); if (!s) return
    compare(H.find(s.screen, "runRowId0").text, "…live0001")
    compare(H.find(s.screen, "runRowTitle0").text, "milestone …alpha")
    compare(H.find(s.screen, "runRowProgress0").text, "1/2")
    compare(H.find(s.screen, "runRowPhase0").text, "implement")
    compare(H.find(s.screen, "runRowAge0").text, "5m")
    compare(H.find(s.screen, "runRowAge0").visible, true)
    compare(H.find(s.screen, "runRowState0").visible, false)
  }

  function test_empty_values_are_left_out() {
    var s = make(sample()); if (!s) return
    compare(H.find(s.screen, "runRowTitle4").text, "…canc0005", "the title falls back to the short id")
    compare(H.find(s.screen, "runRowProgress4").visible, false)
    compare(H.find(s.screen, "runRowPhase4").visible, false)
    compare(H.find(s.screen, "runRowAge4").visible, false)
    compare(H.find(s.screen, "runRowReason4").visible, false)
    compare(H.find(s.screen, "runRowState4").visible, false)
  }

  // ---- titles (4.1)

  // twoProjects(): row 2 is beta's run-b-live0003, milestone zeta.
  function test_a_row_reads_its_title_then_its_short_id_in_dim() {
    var s = make(twoProjects()); if (!s) return
    s.titles.titlesByRoot = { "/home/u/b": { zeta: "Ship zeta" } }
    wait(20)
    var glyph = H.find(s.screen, "runRowGlyph2")
    var title = H.find(s.screen, "runRowTitle2")
    var id = H.find(s.screen, "runRowId2")
    compare(title.text, "Ship zeta")
    compare(id.text, "…live0003")
    compare(id.visible, true)
    compare(String(id.color), String(s.screen.theme.dim), "the short id is dim")
    verify(glyph.x < title.x, "the glyph comes first")
    verify(title.x < id.x, "the short id follows the title")
  }

  function test_the_open_and_another_project_title_from_their_own_maps() {
    var s = make([tagged(run("run-a-live0001", "started", true, { milestone: "m1" }), "/home/u/a", "alpha"),
                  tagged(run("run-b-live0002", "started", true, { milestone: "m1" }), "/home/u/b", "beta")]); if (!s) return
    s.runs.project = "/home/u/a"
    s.titles.titlesByRoot = { "/home/u/a": { m1: "Alpha M" }, "/home/u/b": { m1: "Beta M" } }
    wait(20)
    compare(H.find(s.screen, "runRowTitle0").text, "Alpha M", "the open project's run")
    compare(H.find(s.screen, "runRowId0").text, "…live0001")
    compare(H.find(s.screen, "runRowTitle1").text, "Beta M", "another project's run, from its own map")
    compare(H.find(s.screen, "runRowId1").text, "…live0002")
  }

  function test_without_a_map_the_row_falls_back() {
    var s = make(twoProjects()); if (!s) return
    compare(H.find(s.screen, "runRowTitle2").text, "milestone …zeta", "no map at all")
    s.titles.titlesByRoot = { "/home/u/a": { zeta: "Wrong project" } }
    compare(H.find(s.screen, "runRowTitle2").text, "milestone …zeta", "only another root's map")
    s.titles.titlesByRoot = { "/home/u/b": { zeta: "Ship zeta" } }
    compare(H.find(s.screen, "runRowTitle2").text, "Ship zeta", "a new titlesByRoot re-titles the row")
    var garbage = [{ "/home/u/b": {} }, null, "x", [], { "/home/u/b": null }, { "/home/u/b": "Ship zeta" }]
    for (var i = 0; i < garbage.length; i++) {
      s.titles.titlesByRoot = garbage[i]
      compare(H.find(s.screen, "runRowTitle2").text, "milestone …zeta", "garbage " + i)
      compare(H.find(s.screen, "runRowId2").text, "…live0003", "garbage " + i + " keeps the id")
    }
    s.runs.runs = [run("run-x-none0009", "started", true, { milestone: "zeta" })]
    s.titles.titlesByRoot = { "": { zeta: "Never" } }
    wait(20)
    compare(H.find(s.screen, "runRowTitle0").text, "milestone …zeta", "a run with no project uses no map")
  }

  // Review Focus 1.
  function test_a_long_title_never_pushes_the_short_id_off_the_row() {
    var s = make(twoProjects()); if (!s) return
    var long = ""
    for (var i = 0; i < 40; i++) long += "a very long run title "
    s.titles.titlesByRoot = { "/home/u/b": { zeta: long } }
    wait(20)
    var title = H.find(s.screen, "runRowTitle2")
    var id = H.find(s.screen, "runRowId2")
    compare(title.elide, Text.ElideRight)
    verify(title.width < title.implicitWidth, "the title is elided")
    compare(id.text, "…live0003")
    var right = id.mapToItem(s.screen, 0, 0).x + id.width
    verify(right <= s.screen.width, "the short id stays on the row: right edge " + right)
  }

  function test_an_escalated_row_carries_its_reason() {
    var s = make(sample()); if (!s) return
    var reason = H.find(s.screen, "runRowReason1")
    compare(reason.visible, true)
    compare(reason.text, "tests red after 3 attempts")
    compare(H.find(s.screen, "runRowReason0").visible, false, "only escalated rows")
  }

  function test_dead_and_parked_rows_name_their_state_with_the_age_once() {
    var s = make(sample()); if (!s) return
    compare(H.find(s.screen, "runRowState2").text, "dead - lease lost 7m ago")
    compare(H.find(s.screen, "runRowState2").visible, true)
    compare(H.find(s.screen, "runRowAge2").visible, false, "the age is not shown twice")
    compare(H.find(s.screen, "runRowState3").text, "parked 2h")
    compare(H.find(s.screen, "runRowAge3").visible, false)
  }

  function test_dead_and_parked_rows_without_an_age() {
    var s = make([run("run-x-dead0001", "started", null, {}), run("run-x-park0002", "stopped", null, {}),
                  run("run-x-just0003", "started", false, { heartbeat_at: ago(10000) })]); if (!s) return
    compare(H.find(s.screen, "runRowState0").text, "dead - lease lost")
    compare(H.find(s.screen, "runRowState1").text, "parked")
    compare(H.find(s.screen, "runRowState2").text, "dead - lease lost just now", "never \"just now ago\"")
  }

  function test_clicking_a_row_asks_the_navigator_to_open_that_run() {
    var s = make(sample()); if (!s) return
    tap(H.find(s.screen, "runRow2"))
    compare(s.navi.opened, "run-20261004-dead0003")
  }

  function test_hovering_a_row_moves_the_cursor_through_the_navigator() {
    var s = make(sample()); if (!s) return
    var row = H.find(s.screen, "runRow1")
    mouseMove(row, row.width / 2, row.height / 2)
    compare(s.navi.hovered, 1)
  }

  function test_the_cursor_row_follows_the_navigation_store() {
    var s = make(sample()); if (!s) return
    s.nav.cursorIndex = 2
    compare(H.find(s.screen, "runRow2").hasCursor, true)
    compare(H.find(s.screen, "runRow0").hasCursor, false)
  }

  // ---- chips and search

  function test_the_chips_carry_the_counts() {
    var s = make(sample()); if (!s) return
    compare(H.find(s.screen, "runChipattention").text, "Needs attention 2")
    compare(H.find(s.screen, "runChiplive").text, "Live 1")
    compare(H.find(s.screen, "runChipparked").text, "Parked 1")
    compare(H.find(s.screen, "runChipall").text, "All")
    compare(H.find(s.screen, "runChipall").active, true, "All is active with no filter")
  }

  function test_each_chip_filters_its_rows_and_the_active_one_returns_to_all() {
    var s = make(sample()); if (!s) return
    tap(H.find(s.screen, "runChipattention"))
    compare(s.runs.runFilter, "attention")
    compare(H.find(s.screen, "runChipattention").active, true)
    compare(H.find(s.screen, "runRowId0").text, "…escl0002")
    compare(H.find(s.screen, "runRowId1").text, "…dead0003")
    compare(H.find(s.screen, "runRow2"), null)
    tap(H.find(s.screen, "runChiplive"))
    compare(H.find(s.screen, "runRowId0").text, "…live0001")
    compare(H.find(s.screen, "runRow1"), null)
    tap(H.find(s.screen, "runChipparked"))
    compare(H.find(s.screen, "runRowId0").text, "…park0004")
    compare(H.find(s.screen, "runRow1"), null)
    tap(H.find(s.screen, "runChipparked"))
    compare(s.runs.runFilter, "", "the active chip again means All")
    verify(H.find(s.screen, "runRow5"), "every run is back")
    tap(H.find(s.screen, "runChiplive"))
    tap(H.find(s.screen, "runChipall"))
    compare(s.runs.runFilter, "")
  }

  function test_the_chip_counts_ignore_the_search() {
    var s = make(sample()); if (!s) return
    s.nav.searchQuery = "gamma"
    compare(H.find(s.screen, "runChipattention").text, "Needs attention 2")
    compare(H.find(s.screen, "runRowId0").text, "…dead0003")
    compare(H.find(s.screen, "runRow1"), null)
  }

  function test_a_chip_and_the_search_compose_and_the_no_match_wordings_are_exact() {
    var s = make(sample()); if (!s) return
    s.runs.toggleRunFilter("live")
    s.nav.searchQuery = "beta"
    compare(H.find(s.screen, "runRow0"), null, "beta is not live")
    compare(H.find(s.screen, "runsMessage").text, "No runs match “beta”.")
    s.nav.searchQuery = ""
    s.runs.runs = [sample()[1]]
    compare(H.find(s.screen, "runsMessage").text, "No Live runs.")
    s.runs.toggleRunFilter("attention")
    s.runs.runs = [sample()[0]]
    compare(H.find(s.screen, "runsMessage").text, "No Needs attention runs.")
  }

  // ---- groups

  function test_each_project_gets_a_header_with_its_name_and_counts() {
    var s = make([tagged(run("run-a-live0001", "started", true, {}), "/home/u/a", "alpha"),
                  tagged(run("run-a-escl0002", "escalated", null, {}), "/home/u/a", "alpha"),
                  tagged(run("run-b-park0003", "stopped", null, {}), "/home/u/b", "beta"),
                  tagged(run("run-b-live0004", "started", true, {}), "/home/u/b", "beta")]); if (!s) return
    compare(shown(s, "runGroup0"), true)
    compare(shown(s, "runGroup1"), true)
    compare(H.find(s.screen, "runGroup2"), null)
    compare(H.find(s.screen, "runGroupName0").text, "alpha")
    compare(H.find(s.screen, "runGroupCounts0").text, "1 live · 1 needs attention")
    compare(H.find(s.screen, "runGroupCounts0").visible, true)
    compare(H.find(s.screen, "runGroupName1").text, "beta")
    compare(H.find(s.screen, "runGroupCounts1").text, "1 live · 1 parked")
    verify(topOf(s, "runGroup0") < topOf(s, "runRow0"), "alpha's header above alpha's first run")
    verify(topOf(s, "runRow1") < topOf(s, "runGroup1"), "beta's header after alpha's runs")
    verify(topOf(s, "runGroup1") < topOf(s, "runRow2"), "beta's header above beta's first run")
    compare(H.find(s.screen, "runGroupError0").visible, false, "no snapshot error")
  }

  function test_zero_counts_are_left_out_and_all_zero_hides_the_counts() {
    var s = make([tagged(run("run-g-done0001", "done", null, {}), "/home/u/g", "gamma"),
                  tagged(run("run-g-canc0002", "cancelled", null, {}), "/home/u/g", "gamma"),
                  tagged(run("run-d-park0003", "stopped", null, {}), "/home/u/d", "delta")]); if (!s) return
    compare(H.find(s.screen, "runGroupName0").text, "delta")
    compare(H.find(s.screen, "runGroupCounts0").text, "1 parked")
    compare(H.find(s.screen, "runGroupName1").text, "gamma")
    compare(H.find(s.screen, "runGroupCounts1").text, "")
    compare(H.find(s.screen, "runGroupCounts1").visible, false)
  }

  function test_groups_and_rows_follow_the_display_order() {
    var s = make([tagged(run("run-g-done0001", "done", null, {}), "/home/u/g", "gamma"),
                  tagged(run("run-A-live0002", "started", true, {}), "/home/u/A", "Alpha"),
                  tagged(run("run-b-dead0003", "started", false, {}), "/home/u/b", "beta"),
                  tagged(run("run-A-park0004", "stopped", null, {}), "/home/u/A", "Alpha")]); if (!s) return
    compare(H.find(s.screen, "runGroupName0").text, "beta", "attention first")
    compare(H.find(s.screen, "runGroupName1").text, "Alpha", "then live")
    compare(H.find(s.screen, "runGroupName2").text, "gamma", "then the rest")
    compare(s.runs.filteredRuns.map(function(r) { return r.id }).join(","),
            "run-b-dead0003,run-A-live0002,run-A-park0004,run-g-done0001")
    for (var i = 0; i < 4; i++)
      compare(H.find(s.screen, "runRowId" + i).text, Runs.shortId(s.runs.filteredRuns[i]), "row " + i)
    compare(H.find(s.screen, "runRow4"), null)
    verify(topOf(s, "runRow0") < topOf(s, "runGroup1"))
    verify(topOf(s, "runGroup1") < topOf(s, "runRow1"))
    verify(topOf(s, "runRow2") < topOf(s, "runGroup2"))
    verify(topOf(s, "runGroup2") < topOf(s, "runRow3"))
  }

  function test_runs_without_a_project_get_no_header() {
    var s = make(sample()); if (!s) return
    compare(H.find(s.screen, "runGroup0"), null)
    verify(H.find(s.screen, "runRow0"), "the rows are there")
    compare(H.find(s.screen, "runRowId5").text, "…done0006")
  }

  function test_a_project_name_that_is_empty_shows_the_root() {
    var r = run("run-z-live0001", "started", true, {})
    r.project = { root: "/home/u/z", name: "" }
    var s = make([r]); if (!s) return
    compare(H.find(s.screen, "runGroupName0").text, "/home/u/z")
  }

  function test_the_cursor_on_the_first_run_past_a_header_marks_that_row() {
    var s = make(twoProjects()); if (!s) return
    s.nav.cursorIndex = 2
    compare(H.find(s.screen, "runRow2").hasCursor, true)
    compare(H.find(s.screen, "runRowId2").text, "…live0003", "B's run")
    compare(H.find(s.screen, "runRow0").hasCursor, false)
    compare(H.find(s.screen, "runRow1").hasCursor, false)
    verify(H.find(s.screen, "runGroup1").hasCursor !== true, "a header never has the cursor")
  }

  function test_hovering_a_header_moves_no_cursor_and_a_row_past_it_reports_its_global_index() {
    var s = make(twoProjects()); if (!s) return
    // The pointer rests on the chips (not a row) first, so the move onto the
    // header is an entry: only that entry counts here.
    var chips = H.find(s.screen, "runChips")
    mouseMove(chips, 1, 1)
    s.navi.hovered = -1
    var header = H.find(s.screen, "runGroup1")
    mouseMove(header, header.width / 2, header.height / 2)
    compare(s.navi.hovered, -1)
    var row = H.find(s.screen, "runRow2")
    mouseMove(row, row.width / 2, row.height / 2)
    compare(s.navi.hovered, 2)
  }

  function test_clicking_the_first_run_past_a_header_opens_that_run() {
    var s = make(twoProjects()); if (!s) return
    tap(H.find(s.screen, "runGroup1"))
    compare(s.navi.opened, "", "a header opens nothing")
    tap(H.find(s.screen, "runRow2"))
    compare(s.navi.opened, "run-b-live0003")
  }

  function test_missing_am_shows_no_headers() {
    var s = make(twoProjects()); if (!s) return
    s.runs.amStatus = "missing"
    wait(20)
    compare(shown(s, "runGroup0"), false)
    compare(shown(s, "runsProjectError"), false)
    compare(H.find(s.screen, "runsMessage").text, "am is not installed or not on PATH")
  }

  // Review Focus 1.
  function test_the_counts_are_those_of_the_runs_listed_after_the_search() {
    var s = make(twoProjects()); if (!s) return
    compare(H.find(s.screen, "runGroupCounts0").text, "2 needs attention")
    s.nav.searchQuery = "escl"
    compare(H.find(s.screen, "runGroupName0").text, "alpha")
    compare(H.find(s.screen, "runGroupCounts0").text, "1 needs attention")
    compare(H.find(s.screen, "runGroup1"), null, "beta has nothing listed")
    s.nav.searchQuery = ""
    s.runs.toggleRunFilter("live")
    compare(H.find(s.screen, "runGroupName0").text, "beta", "the chip applies across groups")
    compare(H.find(s.screen, "runGroupCounts0").text, "1 live")
    compare(H.find(s.screen, "runGroup1"), null)
  }

  // Review Focus 2.
  function test_a_new_snapshot_reorders_headers_rows_and_the_cursor() {
    var s = make(twoProjects()); if (!s) return
    s.nav.cursorIndex = 0
    compare(H.find(s.screen, "runRowId0").text, "…escl0001")
    s.runs.runs = [tagged(run("run-a-live0005", "started", true, {}), "/home/u/a", "alpha"),
                   tagged(run("run-b-escl0006", "escalated", null, {}), "/home/u/b", "beta")]
    compare(H.find(s.screen, "runGroupName0").text, "beta")
    compare(H.find(s.screen, "runGroupName1").text, "alpha")
    compare(H.find(s.screen, "runRowId0").text, "…escl0006")
    compare(H.find(s.screen, "runRow0").hasCursor, true)
    compare(H.find(s.screen, "runRowId1").text, "…live0005")
    compare(H.find(s.screen, "runRow1").hasCursor, false)
    compare(H.find(s.screen, "runRow2"), null)
  }

  // Review Focus 3.
  function test_stale_data_dims_rows_but_not_headers() {
    var s = make(twoProjects()); if (!s) return
    s.runs.stale = true
    compare(H.find(s.screen, "runRow0").opacity, 0.5)
    compare(H.find(s.screen, "runGroup0").opacity, 1)
  }

  // ---- snapshot errors

  function test_a_failed_group_shows_its_error_under_its_header() {
    var s = make(twoProjects()); if (!s) return
    s.runs.projectErrors = { "/home/u/b/": "AmTimeout: am status timed out." }
    wait(20)
    var line = H.find(s.screen, "runGroupError1")
    compare(line.visible, true)
    compare(line.text, "AmTimeout: am status timed out.")
    verify(Qt.colorEqual(line.color, s.screen.theme.urgent), "drawn urgent")
    compare(line.wrapMode, Text.WordWrap)
    compare(H.find(s.screen, "runGroupError0").visible, false, "alpha did not fail")
    verify(topOf(s, "runGroupName1") < topOf(s, "runGroupError1"), "under the name")
    verify(topOf(s, "runGroupError1") < topOf(s, "runRow2"), "above the group's first run")
  }

  function test_a_failed_project_with_nothing_listed_still_shows_its_error() {
    var s = make([tagged(run("run-a-live0001", "started", true, {}), "/home/u/a", "alpha")]); if (!s) return
    s.runs.projectRoots = [{ root: "/home/u/a", name: "alpha" }, { root: "/home/u/b", name: "beta" }]
    s.runs.projectErrors = { "/home/u/b": "AmFailed: boom", "/home/u/zzz": "AmFailed: not registered" }
    compare(H.find(s.screen, "runGroupName0").text, "alpha")
    compare(H.find(s.screen, "runGroupName1").text, "beta")
    compare(H.find(s.screen, "runGroupCounts1").visible, false, "no counts")
    compare(H.find(s.screen, "runGroupError1").text, "AmFailed: boom")
    compare(H.find(s.screen, "runGroupError1").visible, true)
    compare(H.find(s.screen, "runGroup2"), null, "an error for an unregistered root shows nothing")
    compare(s.runs.filteredRuns.length, 1, "the extra header adds no run")
    compare(H.find(s.screen, "runRow1"), null)
    s.runs.runs = [tagged(run("run-a-live0001", "started", true, {}), "/home/u/a", "alpha"),
                   tagged(run("run-b-live0002", "started", true, {}), "/home/u/b", "beta")]
    s.runs.toggleRunFilter("parked")
    compare(s.runs.filteredRuns.length, 0)
    compare(H.find(s.screen, "runsMessage").text, "No Parked runs.")
    compare(H.find(s.screen, "runGroupName0").text, "beta", "beta's runs are all filtered out; its error still shows")
    compare(H.find(s.screen, "runGroupError0").text, "AmFailed: boom")
    compare(H.find(s.screen, "runGroup1"), null, "alpha did not fail")
  }

  function test_a_project_filter_shows_a_flat_list_without_headers() {
    var s = make(twoProjects()); if (!s) return
    s.runs.projectFilter = "/home/u/b"
    compare(H.find(s.screen, "runGroup0"), null)
    compare(H.find(s.screen, "runRowId0").text, "…live0003")
    compare(H.find(s.screen, "runRow1"), null)
    compare(shown(s, "runsProjectError"), false)
    s.runs.projectErrors = { "/home/u/b/": "AmTimeout: am status timed out." }
    wait(20)
    var line = H.find(s.screen, "runsProjectError")
    compare(line.visible, true)
    compare(line.text, "AmTimeout: am status timed out.")
    verify(Qt.colorEqual(line.color, s.screen.theme.urgent))
    compare(line.wrapMode, Text.WordWrap)
    verify(topOf(s, "runsProjectError") < topOf(s, "runRow0"), "above the first row")
    compare(H.find(s.screen, "runGroup0"), null, "still no header")
    s.runs.projectFilter = ""
    compare(shown(s, "runsProjectError"), false, "only under a project filter")
    compare(H.find(s.screen, "runGroupError1").text, "AmTimeout: am status timed out.")
    s.runs.amStatus = "missing"
    wait(20)
    compare(shown(s, "runGroup0"), false)
    compare(shown(s, "runGroup1"), false)
    s.runs.projectFilter = "/home/u/b"
    compare(shown(s, "runsProjectError"), false, "am missing hides it too")
  }

  // Review Focus 4.
  function test_malformed_errors_and_registry_entries_show_nothing_and_do_not_throw() {
    var s = make(twoProjects()); if (!s) return
    s.runs.projectRoots = [null, "x", { root: 7 }, { root: "/home/u/c", name: 3 }, { root: "/home/u/a", name: "alpha" }]
    s.runs.projectErrors = { "/home/u/b": null, "/home/u/a": 42, "/home/u/c": "AmFailed: c" }
    compare(H.find(s.screen, "runGroupError0").visible, false, "a non-string error is no error")
    compare(H.find(s.screen, "runGroupError1").visible, false)
    compare(H.find(s.screen, "runGroupName2").text, "/home/u/c", "a non-string name falls back to the root")
    compare(H.find(s.screen, "runGroupError2").text, "AmFailed: c")
    compare(H.find(s.screen, "runGroup3"), null)
    s.runs.projectErrors = null
    compare(H.find(s.screen, "runGroupError0").visible, false)
    compare(H.find(s.screen, "runGroup2"), null)
    s.runs.projectFilter = "/home/u/b"
    compare(shown(s, "runsProjectError"), false)
  }

  // Review Focus 5.
  function test_a_root_registered_twice_gets_one_failed_header() {
    var s = make([]); if (!s) return
    s.runs.projectRoots = [{ root: "/home/u/b", name: "beta" }, { root: "/home/u/b/", name: "beta again" }]
    s.runs.projectErrors = { "/home/u/b": "AmFailed: boom" }
    compare(H.find(s.screen, "runGroupName0").text, "beta", "the first registration's name")
    compare(H.find(s.screen, "runGroup1"), null)
    compare(H.find(s.screen, "runsMessage").text, "No runs yet.", "the status line still speaks about runs")
  }

  // ---- empty and missing

  function test_no_runs_says_so() {
    var s = make([]); if (!s) return
    var msg = H.find(s.screen, "runsMessage")
    compare(msg.text, "No runs yet.")
    compare(msg.visible, true)
  }

  function test_no_projects_registered_says_so_whatever_the_chip() {
    var s = make([]); if (!s) return
    s.runs.projectRoots = []
    var msg = H.find(s.screen, "runsMessage")
    compare(msg.text, "No projects registered.")
    compare(msg.visible, true)
    s.runs.toggleRunFilter("live")
    compare(msg.text, "No projects registered.", "a chip does not change it")
    s.nav.searchQuery = "beta"
    compare(msg.text, "No projects registered.", "nor does a search")
    s.runs.projectRoots = null
    compare(msg.text, "No projects registered.", "a registry that is not a list is empty")
    s.runs.projectRoots = [{ root: "/home/u/a", name: "alpha" }]
    compare(msg.text, "No runs match “beta”.", "a registered project brings the usual wording back")
    s.nav.searchQuery = ""
    compare(msg.text, "No Live runs.")
  }

  function test_missing_am_is_one_message_with_no_chips_or_rows() {
    var s = make(sample()); if (!s) return
    s.runs.stale = true
    s.runs.watchWarning = "CorruptJournal: bad"
    s.runs.lastError = "AmMissing: am is not installed."
    s.runs.amStatus = "missing"
    wait(20)
    var msg = H.find(s.screen, "runsMessage")
    compare(msg.text, "am is not installed or not on PATH")
    compare(msg.visible, true)
    compare(H.find(s.screen, "runChips").visible, false)
    compare(H.find(s.screen, "runRow0"), null, "no rows even before the store empties them")
    compare(H.find(s.screen, "runsFooter").visible, false)
    compare(H.find(s.screen, "runsSchemaBanner").visible, false)
    compare(H.find(s.screen, "runsStaleBanner").visible, false)
    compare(H.find(s.screen, "runsWarning").visible, false)
  }

  // ---- footer and banners

  function test_the_footer_says_whether_the_runs_are_watched() {
    var s = make(sample()); if (!s) return
    var footer = H.find(s.screen, "runsFooter")
    compare(footer.text, "am · watching")
    compare(footer.visible, true)
    s.runs.watching = false
    compare(footer.text, "am · not watching")
    compare(footer.visible, true)
  }

  function test_an_error_shows_the_last_error_in_the_footer_and_keeps_the_rows() {
    var s = make(sample()); if (!s) return
    s.runs.amStatus = "error"
    s.runs.lastError = "AmBadOutput: am status did not print JSON (exit 3)."
    compare(H.find(s.screen, "runsFooter").text, "AmBadOutput: am status did not print JSON (exit 3).")
    verify(H.find(s.screen, "runRow0"), "the last good runs stay")
  }

  function test_a_schema_mismatch_replaces_the_footer_with_a_banner() {
    var s = make(sample()); if (!s) return
    s.runs.amStatus = "schema"
    s.runs.watchSchemaError = "SchemaMismatch: schema 2"
    s.runs.lastError = "something else"
    var banner = H.find(s.screen, "runsSchemaBanner")
    compare(banner.visible, true)
    compare(banner.text, "SchemaMismatch: schema 2")
    compare(H.find(s.screen, "runsFooter").visible, false)
    verify(H.find(s.screen, "runRow0"), "the rows stay beside the banner")
    s.runs.watchSchemaError = ""
    compare(banner.text, "something else", "falls back to lastError")
    s.runs.amStatus = "ok"
    compare(banner.visible, false)
  }

  function test_stale_data_shows_a_banner_and_dims_the_rows() {
    var s = make(sample()); if (!s) return
    compare(H.find(s.screen, "runsStaleBanner").visible, false)
    compare(H.find(s.screen, "runRow0").opacity, 1)
    s.runs.stale = true
    compare(H.find(s.screen, "runsStaleBanner").visible, true)
    compare(H.find(s.screen, "runsStaleBanner").text, "Run data is out of date")
    compare(H.find(s.screen, "runRow0").opacity, 0.5)
  }

  function test_a_watch_warning_shows_one_line() {
    var s = make(sample()); if (!s) return
    var line = H.find(s.screen, "runsWarning")
    compare(line.visible, false)
    s.runs.watchWarning = "CorruptJournal: journal line 12 is not JSON"
    compare(line.visible, true)
    compare(line.text, "CorruptJournal: journal line 12 is not JSON")
  }

  // ---- the announced hello in the footer

  function test_the_footer_names_am_and_schema_1_from_the_hello() {
    var s = make(sample()); if (!s) return
    var footer = H.find(s.screen, "runsFooter")
    s.runs.amVersion = "0.1.0"
    s.runs.amSchema = 1
    compare(footer.text, "am 0.1.0 · schema 1 · watching")
    s.runs.watching = false
    compare(footer.text, "am 0.1.0 · schema 1 · not watching")
  }

  function test_the_footer_names_schema_2_from_the_hello() {
    var s = make(sample()); if (!s) return
    var footer = H.find(s.screen, "runsFooter")
    s.runs.amVersion = "0.2.0"
    s.runs.amSchema = 2
    compare(footer.text, "am 0.2.0 · schema 2 · watching")
  }

  function test_the_footer_without_a_hello_names_no_schema() {
    var s = make(sample()); if (!s) return
    var footer = H.find(s.screen, "runsFooter")
    compare(footer.text, "am · watching")
    s.runs.amSchema = 1
    s.runs.amVersion = "0.1.0"
    compare(footer.text, "am 0.1.0 · schema 1 · watching", "a hello arrives")
    s.runs.amSchema = 0
    s.runs.amVersion = ""
    compare(footer.text, "am · watching", "the hello is forgotten")
  }

  function test_the_footer_leaves_out_an_unknown_version() {
    var s = make(sample()); if (!s) return
    var footer = H.find(s.screen, "runsFooter")
    s.runs.amSchema = 2
    s.runs.amVersion = ""
    compare(footer.text, "am · schema 2 · watching")
  }

  function test_the_footer_shows_no_version_without_a_schema() {
    var s = make(sample()); if (!s) return
    var footer = H.find(s.screen, "runsFooter")
    s.runs.amVersion = "0.1.0"
    compare(footer.text, "am · watching")
    s.runs.watching = false
    compare(footer.text, "am · not watching")
  }

  function test_flash_and_error_still_win_over_the_announced_hello() {
    var s = make(sample()); if (!s) return
    var footer = H.find(s.screen, "runsFooter")
    s.runs.amSchema = 2
    s.runs.amVersion = "0.2.0"
    s.control.flashText = "The run has finished"
    compare(footer.text, "The run has finished", "the flash alone, with no am prefix")
    s.control.flashText = ""
    compare(footer.text, "am 0.2.0 · schema 2 · watching")
    s.runs.amStatus = "error"
    s.runs.lastError = "AmFailed: boom"
    compare(footer.text, "AmFailed: boom", "the error alone, with no am prefix")
    s.control.flashText = "The run is still running"
    compare(footer.text, "The run is still running", "the flash wins over the error line")
    s.control.flashText = ""
    compare(footer.text, "AmFailed: boom")
    s.runs.amStatus = "ok"
    compare(footer.text, "am 0.2.0 · schema 2 · watching")
  }

  function test_the_hello_does_not_unhide_the_footer() {
    var s = make(sample()); if (!s) return
    var footer = H.find(s.screen, "runsFooter")
    s.runs.amSchema = 1
    s.runs.amVersion = "0.1.0"
    compare(footer.visible, true)
    s.runs.amStatus = "missing"
    wait(20)
    compare(footer.visible, false, "am is missing")
    s.runs.amStatus = "schema"
    wait(20)
    compare(footer.visible, false, "the schema banner shows")
  }

  // Review Focus 1.
  function test_a_hello_that_arrives_under_the_error_line_shows_once_the_error_clears() {
    var s = make(sample()); if (!s) return
    var footer = H.find(s.screen, "runsFooter")
    s.runs.amStatus = "error"
    s.runs.lastError = "AmFailed: boom"
    s.runs.amSchema = 1
    s.runs.amVersion = "0.1.0"
    compare(footer.text, "AmFailed: boom")
    s.runs.amStatus = "ok"
    compare(footer.text, "am 0.1.0 · schema 1 · watching")
  }

  // Review Focus 2.
  function test_a_hello_forgotten_under_a_flash_is_not_shown_after_it() {
    var s = make(sample()); if (!s) return
    var footer = H.find(s.screen, "runsFooter")
    s.runs.amSchema = 2
    s.runs.amVersion = "0.2.0"
    s.control.flashText = "The run has finished"
    s.runs.amSchema = 0
    s.runs.amVersion = ""
    s.runs.watching = false
    compare(footer.text, "The run has finished")
    s.control.flashText = ""
    compare(footer.text, "am · not watching")
  }

  // Review Focus 3.
  function test_the_footer_comes_back_from_the_schema_banner_with_the_hello() {
    var s = make(sample()); if (!s) return
    var footer = H.find(s.screen, "runsFooter")
    s.runs.amSchema = 2
    s.runs.amVersion = "0.2.0"
    s.runs.amStatus = "schema"
    wait(20)
    compare(footer.visible, false)
    s.runs.amStatus = "ok"
    wait(20)
    compare(footer.visible, true)
    compare(footer.text, "am 0.2.0 · schema 2 · watching")
  }

  // Review Focus 4.
  function test_a_two_digit_schema_prints_as_a_plain_integer() {
    var s = make(sample()); if (!s) return
    var footer = H.find(s.screen, "runsFooter")
    s.runs.amSchema = 10
    s.runs.amVersion = "1.0.0"
    compare(footer.text, "am 1.0.0 · schema 10 · watching")
  }

  // Review Focus 5.
  function test_a_pre_release_version_prints_verbatim() {
    var s = make(sample()); if (!s) return
    var footer = H.find(s.screen, "runsFooter")
    s.runs.amSchema = 2
    s.runs.amVersion = "0.2.0-rc.1"
    compare(footer.text, "am 0.2.0-rc.1 · schema 2 · watching")
  }

  // ---- robustness and visibility

  function test_malformed_runs_render_without_throwing() {
    var s = make([{}, { id: 42, status: 7, lease: "x", rows: "y", tree: null, milestone_id: {} },
                  run("run-20261004-good0007", "done", null, {})]); if (!s) return
    compare(H.find(s.screen, "runRowId0").text, "…")
    compare(H.find(s.screen, "runRowGlyph0").visible, false, "an unknown state has no glyph")
    compare(H.find(s.screen, "runRowId1").text, "…")
    compare(H.find(s.screen, "runRowTitle1").text, "…")
    compare(H.find(s.screen, "runRowProgress1").visible, false)
    compare(H.find(s.screen, "runRowId2").text, "…good0007")
    compare(H.find(s.screen, "runChipall").text, "All")
  }

  function test_the_screen_is_hidden_outside_its_section() {
    var s = make(sample()); if (!s) return
    compare(s.screen.visible, true)
    s.nav.viewMode = "run"
    compare(s.screen.visible, false)
    s.nav.viewMode = "runs"
    s.app.projects = { selectedProject: null }
    compare(s.screen.visible, true, "no project: the Runs list still shows")
    compare(H.find(s.screen, "runsNotifyRow").visible, true, "and so does the notify switch")
  }

  // ---- run controls (S2 4.2)

  SignalSpy { id: cancelSpy; signalName: "cancelRequested" }

  // A part of row i's RunControls; search inside the row's controls, since
  // every row has a runControlPause.
  function ctl(s, i, name) { return H.find(H.find(s.screen, "runRowControls" + i), "runControl" + name) }

  // 13
  function test_a_rows_buttons_show_only_while_it_has_the_cursor() {
    var s = make(sample()); if (!s) return
    s.nav.cursorIndex = 0
    wait(20)
    compare(ctl(s, 0, "Pause").visible, true)
    compare(ctl(s, 0, "Cancel").visible, true)
    compare(ctl(s, 3, "Resume").visible, false, "the parked row has no cursor")
    s.nav.cursorIndex = 3
    wait(20)
    compare(ctl(s, 0, "Pause").visible, false)
    compare(ctl(s, 3, "Resume").visible, true)
    s.control.pending = { "run-20261004-live0001": "pause" }
    compare(ctl(s, 0, "Pause").visible, true, "a pending request keeps its button")
    compare(ctl(s, 0, "Pause").text, "Pause requested…")
    compare(ctl(s, 0, "Pause").enabled, false)
    s.nav.cursorIndex = 5
    wait(20)
    compare(H.find(s.screen, "runRowControls5").height, 0, "a done run shows nothing under the cursor")
  }

  // 14
  function test_pause_and_resume_go_to_the_store_and_do_not_open_the_run() {
    var s = make(sample()); if (!s) return
    s.nav.cursorIndex = 0
    wait(20)
    tap(ctl(s, 0, "Pause"))
    compare(s.control.controlCalls.join(","), "pause|run-20261004-live0001")
    compare(s.navi.opened, "", "the button is not the row")
    s.nav.cursorIndex = 3
    wait(20)
    tap(ctl(s, 3, "Resume"))
    compare(s.control.controlCalls.join(","), "pause|run-20261004-live0001,resume|run-20261004-park0004")
    compare(s.navi.opened, "")
  }

  // 15
  function test_cancel_asks_the_owner_and_never_the_store() {
    var s = make(sample()); if (!s) return
    cancelSpy.target = s.screen
    cancelSpy.clear()
    s.nav.cursorIndex = 0
    wait(20)
    tap(ctl(s, 0, "Cancel"))
    compare(cancelSpy.count, 1)
    compare(cancelSpy.signalArguments[0][0], "run-20261004-live0001")
    compare(s.control.controlCalls.length, 0)
    compare(s.navi.opened, "")
  }

  // 16
  function test_the_error_and_waiting_lines_show_under_their_own_run_only() {
    var s = make(sample()); if (!s) return
    s.nav.cursorIndex = -1
    s.control.lastControlError = "The run is not running"
    s.control.lastControlErrorRunId = "run-20261004-escl0002"
    wait(20)
    compare(ctl(s, 1, "Error").visible, true, "whether or not the row has the cursor")
    compare(ctl(s, 1, "Error").text, "The run is not running")
    compare(ctl(s, 0, "Error").visible, false)
    compare(ctl(s, 2, "Error").visible, false)
    s.control.pending = { "run-20261004-dead0003": "resume" }
    s.control.stillWaiting = { "run-20261004-dead0003": true }
    compare(ctl(s, 2, "Waiting").visible, true)
    compare(ctl(s, 2, "Waiting").text, "still waiting — the run may be between phases or dead")
    compare(ctl(s, 2, "Resume").text, "Resume requested…")
    compare(ctl(s, 0, "Waiting").visible, false)
  }

  // Review Focus 2.
  function test_a_run_id_like_constructor_is_not_pending() {
    var s = make([run("constructor", "started", true, {}), run("__proto__", "stopped", null, {})]); if (!s) return
    s.nav.cursorIndex = 0
    wait(20)
    compare(ctl(s, 0, "Pause").text, "Pause")
    compare(ctl(s, 0, "Pause").enabled, true)
    compare(ctl(s, 0, "Waiting").visible, false)
    compare(ctl(s, 0, "Error").visible, false)
    s.nav.cursorIndex = 1
    wait(20)
    compare(ctl(s, 1, "Resume").text, "Resume")
    compare(ctl(s, 1, "Resume").enabled, true)
  }

  // ---- the footer flash (S2 4.3)

  // 14
  function test_a_flash_takes_the_footer_and_then_gives_it_back() {
    var s = make(sample()); if (!s) return
    var footer = H.find(s.screen, "runsFooter")
    s.control.flashText = "The run has finished"
    compare(footer.text, "The run has finished")
    compare(footer.visible, true)
    s.control.flashText = ""
    compare(footer.text, "am · watching")
    s.runs.amStatus = "error"
    s.runs.lastError = "AmFailed: boom"
    s.control.flashText = "The run is still running"
    compare(footer.text, "The run is still running", "the flash wins over the error line")
    s.control.flashText = ""
    compare(footer.text, "AmFailed: boom")
    s.runs.amStatus = "schema"
    s.runs.watchSchemaError = "SchemaMismatch: schema 2"
    compare(footer.visible, false)
    s.control.flashText = "A request for this run is pending"
    compare(footer.visible, true, "a flash shows even beside the schema banner")
    compare(footer.text, "A request for this run is pending")
    s.control.flashText = ""
    compare(footer.visible, false)
  }

  // ---- the Notify on escalation switch (S2 4.4)

  // 25
  function test_the_notify_switch_reads_and_asks_the_store() {
    var s = make(sample()); if (!s) return
    var row = H.find(s.screen, "runsNotifyRow")
    var toggle = H.find(s.screen, "runsNotifyToggle")
    verify(row, "the switch row")
    verify(toggle, "the switch")
    compare(H.find(s.screen, "runsNotifyLabel").text, "Notify on escalation")
    compare(toggle.checked, false)
    s.control.notifyOnEscalation = true
    compare(toggle.checked, true)
    s.control.notifyOnEscalation = false
    compare(toggle.checked, false)
    toggle.toggled()
    compare(s.control.notifyCalls.join(","), "true", "asked once, for the flipped value")
    compare(toggle.checked, false, "the store decides; this stub did not flip it")
    compare(row.visible, true)
    verify(row.y < H.find(s.screen, "runsFooter").y, "above the footer")
    s.runs.amStatus = "missing"
    wait(20)
    compare(row.visible, true, "the setting is the project's, not am's")
  }

  // ---- project chips (4.3)

  // 1
  function test_project_chips_without_an_open_project() {
    var s = make(twoProjects()); if (!s) return
    compare(shown(s, "runProjectChips"), true)
    compare(projectChipText(s, "all"), "All projects")
    compare(projectChipText(s, "/home/u/a"), "alpha 2")
    compare(projectChipText(s, "/home/u/b"), "beta 1")
    compare(H.find(s.screen, "runProjectChipthis"), null)
    compare(projectChipIds(s), "all,/home/u/a,/home/u/b", "alpha (attention) before beta (live)")
    var a = H.find(s.screen, "runProjectChip/home/u/a")
    var b = H.find(s.screen, "runProjectChip/home/u/b")
    verify(a.mapToItem(s.screen, 0, 0).x < b.mapToItem(s.screen, 0, 0).x, "alpha is drawn left of beta")
  }

  // 2
  function test_an_open_project_adds_this_project_in_place_of_its_own_chip() {
    var s = make(twoProjects()); if (!s) return
    s.runs.project = "/home/u/a/"
    compare(projectChipText(s, "this"), "This project 2")
    compare(H.find(s.screen, "runProjectChip/home/u/a"), null, "alpha is listed once, as This project")
    compare(projectChipText(s, "/home/u/b"), "beta 1")
    compare(projectChipIds(s), "all,this,/home/u/b")
  }

  // 4
  function test_the_row_hides_with_one_project_and_none_open() {
    var all = twoProjects()
    var s = make([all[0], all[2]]); if (!s) return
    compare(shown(s, "runProjectChips"), false, "one project with runs, none open")
    s.runs.project = "/home/u/a"
    compare(shown(s, "runProjectChips"), true)
    compare(projectChipIds(s), "all,this")
    compare(projectChipText(s, "this"), "This project 2")
    s.runs.project = "/home/u/b"
    compare(projectChipIds(s), "all,this,/home/u/a", "the open project is not the one with runs")
    compare(projectChipText(s, "this"), "This project 0")
    s.runs.project = ""
    s.runs.runs = sample()
    compare(shown(s, "runProjectChips"), false, "runs with no project are no project")
    s.runs.runs = []
    compare(shown(s, "runProjectChips"), false, "no runs, none open")
    s.runs.project = "/home/u/c"
    compare(shown(s, "runProjectChips"), true)
    compare(projectChipIds(s), "all,this")
    compare(projectChipText(s, "this"), "This project 0")
  }

  // 11
  function test_the_project_chips_sit_above_the_status_chips() {
    var s = make(twoProjects()); if (!s) return
    s.runs.watchWarning = "CorruptJournal: bad"
    wait(20)
    verify(topOf(s, "runsWarning") < topOf(s, "runProjectChips"), "below the banners")
    verify(topOf(s, "runProjectChips") < topOf(s, "runChips"), "above the status chips")
  }

  // 12
  function test_missing_am_hides_the_project_chips() {
    var s = make(twoProjects()); if (!s) return
    s.runs.amStatus = "missing"
    wait(20)
    compare(shown(s, "runProjectChips"), false)
    s.runs.amStatus = "schema"
    wait(20)
    compare(shown(s, "runProjectChips"), true, "a schema mismatch keeps them, as it keeps the status chips")
    s.runs.amStatus = "error"
    s.runs.stale = true
    wait(20)
    compare(shown(s, "runProjectChips"), true, "an error or stale data keeps them")
  }

  // 13
  function test_project_chip_labels_fall_back_to_the_root_and_follow_group_order() {
    var nameless = run("run-n-park0004", "stopped", null, {})
    nameless.project = { root: "/home/u/n", name: "" }
    var s = make([tagged(run("run-g-done0001", "done", null, {}), "/home/u/g", "gamma"),
                  tagged(run("run-a-live0002", "started", true, {}), "/home/u/a", "Alpha"),
                  tagged(run("run-b-escl0003", "escalated", null, {}), "/home/u/b", "beta"),
                  nameless]); if (!s) return
    compare(projectChipIds(s), "all,/home/u/b,/home/u/a,/home/u/n,/home/u/g",
            "attention, live, then name case-blind with the empty name first")
    compare(projectChipText(s, "/home/u/b"), "beta 1")
    compare(projectChipText(s, "/home/u/a"), "Alpha 1")
    compare(projectChipText(s, "/home/u/n"), "/home/u/n 1")
    compare(projectChipText(s, "/home/u/g"), "gamma 1")
  }

  // 14
  function test_a_non_string_project_shows_no_this_chip_and_does_not_throw() {
    var s = make(twoProjects()); if (!s) return
    s.runs.project = undefined
    compare(H.find(s.screen, "runProjectChipthis"), null)
    compare(projectChipIds(s), "all,/home/u/a,/home/u/b")
    s.runs.project = 7
    compare(H.find(s.screen, "runProjectChipthis"), null)
    compare(projectChipIds(s), "all,/home/u/a,/home/u/b")
  }

  // Review Focus 1.
  function test_many_project_chips_wrap_and_keep_the_status_chips_below() {
    var names = ["first-long-project-name", "second-long-project-name", "third-long-project-name",
                 "fourth-long-project-name", "fifth-long-project-name", "sixth-long-project-name"]
    var list = []
    for (var i = 0; i < names.length; i++)
      list.push(tagged(run("run-p" + i + "-done000" + i, "done", null, {}), "/home/u/p" + i, names[i]))
    var s = make(list); if (!s) return
    var row = H.find(s.screen, "runProjectChips")
    var first = H.find(s.screen, "runProjectChip/home/u/p0")
    verify(row.height > first.height * 2, "the chips wrap onto more lines")
    verify(topOf(s, "runProjectChips") + row.height <= topOf(s, "runChips"), "the status chips stay below")
    compare(shown(s, "runChips"), true)
    for (var p = 0; p < names.length; p++) {
      var chip = H.find(s.screen, "runProjectChip/home/u/p" + p)
      verify(chip.mapToItem(s.screen, 0, 0).x + chip.width <= s.screen.width, "chip " + p + " stays inside the screen")
    }
  }

  // 3
  function test_all_projects_is_the_default() {
    var s = make(twoProjects()); if (!s) return
    s.runs.project = "/home/u/a"
    compare(s.runs.projectFilter, "")
    compare(H.find(s.screen, "runProjectChipall").active, true)
    compare(H.find(s.screen, "runProjectChipthis").active, false)
    compare(H.find(s.screen, "runProjectChip/home/u/b").active, false)
  }

  // 5
  function test_a_project_chip_filters_and_clicking_it_again_returns_to_all() {
    var s = make(twoProjects()); if (!s) return
    tap(H.find(s.screen, "runProjectChip/home/u/b"))
    compare(JSON.stringify(s.runs.projectToggles), "[\"/home/u/b\"]", "one call, with beta's root")
    compare(s.runs.projectFilter, "/home/u/b")
    compare(H.find(s.screen, "runProjectChip/home/u/b").active, true)
    compare(H.find(s.screen, "runProjectChipall").active, false)
    compare(H.find(s.screen, "runGroup0"), null, "flat")
    compare(H.find(s.screen, "runRowId0").text, "…live0003")
    compare(H.find(s.screen, "runRow1"), null)
    tap(H.find(s.screen, "runProjectChip/home/u/b"))
    compare(s.runs.projectToggles.length, 2)
    compare(s.runs.projectFilter, "")
    compare(H.find(s.screen, "runProjectChipall").active, true)
    compare(H.find(s.screen, "runProjectChip/home/u/b").active, false)
    compare(H.find(s.screen, "runGroupName0").text, "alpha", "grouped again")
  }

  // 6
  function test_all_projects_and_this_project_ask_the_store() {
    var s = make(twoProjects()); if (!s) return
    s.runs.toggleProjectFilter("/home/u/b")
    s.runs.projectToggles = []
    tap(H.find(s.screen, "runProjectChipall"))
    compare(JSON.stringify(s.runs.projectToggles), "[\"\"]")
    compare(s.runs.projectFilter, "")
    s.runs.project = "/home/u/a"
    s.runs.projectToggles = []
    tap(H.find(s.screen, "runProjectChipthis"))
    compare(JSON.stringify(s.runs.projectToggles), "[\"/home/u/a\"]")
    compare(s.runs.projectFilter, "/home/u/a")
    compare(H.find(s.screen, "runProjectChipthis").active, true)
    compare(H.find(s.screen, "runProjectChipall").active, false)
    compare(H.find(s.screen, "runRowId0").text, "…escl0001")
    compare(H.find(s.screen, "runRowId1").text, "…dead0002")
    compare(H.find(s.screen, "runRow2"), null, "alpha's runs only")
    s.runs.project = "/home/u/a/"
    compare(H.find(s.screen, "runProjectChipthis").active, true, "a trailing / on the open project still matches")
  }

  // 7
  function test_this_project_with_no_runs_stays_on_all() {
    var s = make(twoProjects()); if (!s) return
    s.runs.project = "/home/u/c"
    compare(projectChipText(s, "this"), "This project 0")
    tap(H.find(s.screen, "runProjectChipthis"))
    compare(JSON.stringify(s.runs.projectToggles), "[\"/home/u/c\"]")
    compare(s.runs.projectFilter, "")
    compare(H.find(s.screen, "runProjectChipall").active, true)
    compare(H.find(s.screen, "runProjectChipthis").active, false)
    compare(H.find(s.screen, "runGroupName0").text, "alpha", "still grouped")
  }

  // 10
  function test_a_vanished_filtered_project_falls_back_to_all_projects() {
    var s = make(twoProjects()); if (!s) return
    tap(H.find(s.screen, "runProjectChip/home/u/b"))
    compare(s.runs.projectFilter, "/home/u/b")
    var all = twoProjects()
    s.runs.runs = [all[0], all[2]]
    compare(s.runs.projectFilter, "", "the store fell back")
    compare(H.find(s.screen, "runProjectChipall").active, true)
    compare(H.find(s.screen, "runProjectChip/home/u/b"), null, "beta's chip is gone")
    compare(H.find(s.screen, "runGroupName0").text, "alpha", "headers are back")
    compare(H.find(s.screen, "runChipattention").text, "Needs attention 2")
    compare(H.find(s.screen, "runChiplive").text, "Live 0")
  }

  // Review Focus 2.
  function test_a_new_snapshot_reorders_the_chips_and_the_active_one_stays_active() {
    var s = make(twoProjects()); if (!s) return
    tap(H.find(s.screen, "runProjectChip/home/u/b"))
    s.runs.runs = [tagged(run("run-a-done0001", "done", null, {}), "/home/u/a", "alpha"),
                   tagged(run("run-b-escl0003", "escalated", null, {}), "/home/u/b", "beta")]
    compare(projectChipIds(s), "all,/home/u/b,/home/u/a", "beta needs attention now")
    compare(s.runs.projectFilter, "/home/u/b")
    compare(H.find(s.screen, "runProjectChip/home/u/b").active, true)
    compare(H.find(s.screen, "runProjectChip/home/u/a").active, false)
    compare(H.find(s.screen, "runRowId0").text, "…escl0003")
  }

  // Review Focus 4.
  function test_opening_the_filtered_project_moves_the_active_chip_to_this_project() {
    var s = make(twoProjects()); if (!s) return
    tap(H.find(s.screen, "runProjectChip/home/u/b"))
    s.runs.project = "/home/u/b"
    compare(s.runs.projectFilter, "/home/u/b", "a project switch does not touch the filter")
    compare(H.find(s.screen, "runProjectChip/home/u/b"), null, "beta is listed once, as This project")
    compare(H.find(s.screen, "runProjectChipthis").active, true)
    compare(projectChipText(s, "this"), "This project 1")
    compare(projectChipText(s, "/home/u/a"), "alpha 2")
    s.runs.project = ""
    compare(H.find(s.screen, "runProjectChip/home/u/b").active, true)
  }

  // 8
  function test_status_chip_counts_apply_within_the_project_filter() {
    var s = make(twoProjects()); if (!s) return
    compare(H.find(s.screen, "runChipattention").text, "Needs attention 2")
    compare(H.find(s.screen, "runChiplive").text, "Live 1")
    s.runs.toggleProjectFilter("/home/u/b")
    compare(H.find(s.screen, "runChipattention").text, "Needs attention 0")
    compare(H.find(s.screen, "runChiplive").text, "Live 1")
    compare(H.find(s.screen, "runChipparked").text, "Parked 0")
    s.runs.toggleProjectFilter("/home/u/a")
    compare(H.find(s.screen, "runChipattention").text, "Needs attention 2")
    compare(H.find(s.screen, "runChiplive").text, "Live 0")
  }

  // 9
  function test_a_status_chip_and_the_project_filter_compose_and_project_counts_stay_whole() {
    var s = make(twoProjects()); if (!s) return
    s.runs.toggleProjectFilter("/home/u/a")
    tap(H.find(s.screen, "runChiplive"))
    compare(H.find(s.screen, "runRow0"), null, "alpha has no live run")
    compare(H.find(s.screen, "runsMessage").text, "No Live runs.")
    s.runs.toggleProjectFilter("")
    tap(H.find(s.screen, "runChipattention"))
    compare(projectChipText(s, "/home/u/b"), "beta 1", "beta's chip keeps its full count")
    compare(projectChipText(s, "/home/u/a"), "alpha 2")
  }

  // Review Focus 3.
  function test_the_search_changes_neither_project_chips_nor_status_counts() {
    var s = make(twoProjects()); if (!s) return
    s.nav.searchQuery = "zeta"
    compare(H.find(s.screen, "runRowId0").text, "…live0003")
    compare(H.find(s.screen, "runRow1"), null)
    compare(projectChipText(s, "/home/u/a"), "alpha 2", "alpha's runs are all searched out; its chip stays")
    compare(projectChipText(s, "/home/u/b"), "beta 1")
    s.runs.toggleProjectFilter("/home/u/a")
    compare(H.find(s.screen, "runChipattention").text, "Needs attention 2", "counts within the filter, not the search")
    compare(H.find(s.screen, "runRow0"), null)
  }

  // Review Focus 5.
  function test_runs_without_a_project_count_under_all_projects_only() {
    var s = make(sample().concat(twoProjects())); if (!s) return
    compare(projectChipIds(s), "all,/home/u/a,/home/u/b", "untagged runs get no chip")
    compare(H.find(s.screen, "runChipattention").text, "Needs attention 4")
    compare(H.find(s.screen, "runChiplive").text, "Live 2")
    compare(H.find(s.screen, "runChipparked").text, "Parked 1")
    s.runs.toggleProjectFilter("/home/u/a")
    compare(H.find(s.screen, "runChipattention").text, "Needs attention 2")
    compare(H.find(s.screen, "runChiplive").text, "Live 0")
    compare(H.find(s.screen, "runChipparked").text, "Parked 0")
  }

  // ---- Open project (4.4)

  // Row i's Open project button; the test fails when the row has none.
  function openButton(s, i) {
    var b = H.find(s.screen, "runRowOpenProject" + i)
    verify(b, "row " + i + " has an Open project button")
    return b
  }

  // The stub registry: alpha's selected, `list` the registry.
  function registry(list) {
    return { selectedProject: { root_path: "/home/u/a", name: "alpha" }, projects: list }
  }

  // twoProjects(): rows 0 and 1 are alpha's, row 2 is beta's.
  // 1
  function test_open_project_shows_on_the_cursor_row_of_another_projects_run() {
    var s = make(twoProjects()); if (!s) return
    s.runs.project = "/home/u/a"
    s.nav.cursorIndex = 2
    wait(20)
    compare(openButton(s, 2).visible, true)
    compare(openButton(s, 2).text, "Open project")
    s.nav.cursorIndex = 0
    wait(20)
    compare(openButton(s, 0).visible, false, "alpha is the open project")
    compare(openButton(s, 2).visible, false, "beta's row lost the cursor")
  }

  // 2
  function test_open_project_is_hidden_off_the_cursor() {
    var s = make(twoProjects()); if (!s) return
    s.runs.project = "/home/u/a"
    s.nav.cursorIndex = 0
    wait(20)
    var row = H.find(s.screen, "runRow2")
    compare(openButton(s, 2).visible, false)
    var before = row.height
    s.nav.cursorIndex = 2
    wait(20)
    compare(openButton(s, 2).visible, true)
    s.nav.cursorIndex = 0
    wait(20)
    compare(openButton(s, 2).visible, false)
    compare(row.height, before, "the row is as tall as before the cursor came")
  }

  // 3
  function test_open_project_is_hidden_for_the_open_project_with_a_trailing_slash() {
    var s = make(twoProjects()); if (!s) return
    s.runs.project = "/home/u/a/"
    s.nav.cursorIndex = 0
    wait(20)
    compare(openButton(s, 0).visible, false)
    s.nav.cursorIndex = 1
    wait(20)
    compare(openButton(s, 1).visible, false)
    s.nav.cursorIndex = 2
    wait(20)
    compare(openButton(s, 2).visible, true, "beta is not the open project")
  }

  // 4
  function test_with_no_project_open_every_registered_projects_run_shows_open_project() {
    var s = make(twoProjects()); if (!s) return
    s.runs.project = ""
    s.nav.cursorIndex = 0
    wait(20)
    compare(openButton(s, 0).visible, true, "alpha's run")
    s.nav.cursorIndex = 2
    wait(20)
    compare(openButton(s, 2).visible, true, "beta's run")
  }

  // 5
  function test_open_project_is_hidden_for_a_run_with_no_project_or_an_unregistered_one() {
    var s = make([run("run-20261004-plain001", "started", true, {}),
                  tagged(run("run-c-live0009", "started", true, {}), "/home/u/c", "gamma")]); if (!s) return
    s.runs.project = "/home/u/a"
    for (var i = 0; i < 2; i++) {
      s.nav.cursorIndex = i
      wait(20)
      compare(openButton(s, i).visible, false, "row " + i)
    }
  }

  // 6
  function test_open_project_tolerates_a_missing_registry() {
    var s = make(twoProjects()); if (!s) return
    s.runs.project = "/home/u/a"
    s.nav.cursorIndex = 2
    wait(20)
    compare(openButton(s, 2).visible, true, "the full registry shows it")
    var lists = [undefined, null, "abc", 7, ({ length: 1 })]
    for (var i = 0; i < lists.length; i++) {
      s.app.projects = registry(lists[i])
      compare(openButton(s, 2).visible, false, "registry " + i)
    }
    s.app.projects = { selectedProject: { root_path: "/home/u/a", name: "alpha" } }
    compare(openButton(s, 2).visible, false, "no projects key at all")
  }

  // Review Focus 2.
  function test_a_malformed_run_project_hides_open_project_without_throwing() {
    var bad = [run("run-x-null0001", "started", true, {}), run("run-x-strg0002", "started", true, {}),
               run("run-x-nort0003", "started", true, {}), run("run-x-arry0004", "started", true, {})]
    bad[0].project = null
    bad[1].project = "/home/u/b"
    bad[2].project = { root: 7, name: "beta" }
    bad[3].project = ["/home/u/b"]
    var s = make(bad.concat([{}])); if (!s) return
    s.runs.project = "/home/u/a"
    for (var i = 0; i < 5; i++) {
      s.nav.cursorIndex = i
      wait(20)
      compare(openButton(s, i).visible, false, "row " + i)
    }
  }

  // Review Focus 3.
  function test_malformed_registry_entries_are_skipped() {
    var s = make(twoProjects()); if (!s) return
    s.runs.project = "/home/u/a"
    s.app.projects = registry([null, 5, "/home/u/b", { root_path: 7 }, { name: "no root" }])
    s.nav.cursorIndex = 2
    wait(20)
    compare(openButton(s, 2).visible, false, "no well-formed entry for beta")
    s.app.projects = registry([null, { root_path: 7 }, { root_path: "/home/u/b/", name: "beta" }])
    compare(openButton(s, 2).visible, true, "the well-formed entry past the bad ones")
  }

  // Review Focus 4.
  function test_open_project_follows_the_open_project_and_the_registry() {
    var s = make(twoProjects()); if (!s) return
    s.runs.project = "/home/u/a"
    s.nav.cursorIndex = 2
    wait(20)
    compare(openButton(s, 2).visible, true)
    s.runs.project = "/home/u/b"
    compare(openButton(s, 2).visible, false, "beta is open now")
    s.runs.project = "/home/u/a"
    compare(openButton(s, 2).visible, true)
    s.app.projects = registry([{ root_path: "/home/u/a", name: "alpha" }])
    compare(openButton(s, 2).visible, false, "beta left the registry")
    s.app.projects = registry([{ root_path: "/home/u/a", name: "alpha" }, { root_path: "/home/u/b", name: "beta" }])
    compare(openButton(s, 2).visible, true, "beta is back")
  }

  // 7
  function test_open_project_click_chooses_the_registry_entry_and_does_not_open_the_run() {
    var s = make(twoProjects()); if (!s) return
    s.runs.project = "/home/u/a"
    s.nav.cursorIndex = 2
    wait(20)
    tap(openButton(s, 2))
    compare(s.navi.chosen.length, 1)
    compare(s.navi.chosen[0].name, "beta")
    verify(s.navi.chosen[0] === s.app.projects.projects[1], "the registry's own beta entry")
    compare(s.navi.opened, "", "the button is not the row")
    compare(s.runs.projectToggles.length, 0, "the project filter is not touched")
    compare(s.runs.projectFilter, "")
  }

  // 8
  function test_open_project_picks_the_first_of_two_entries_with_one_root() {
    var s = make(twoProjects()); if (!s) return
    s.runs.project = "/home/u/a"
    s.app.projects = registry([{ root_path: "/home/u/a", name: "alpha" },
                               { root_path: "/home/u/b/", name: "beta-1" },
                               { root_path: "/home/u/b", name: "beta-2" }])
    s.nav.cursorIndex = 2
    wait(20)
    tap(openButton(s, 2))
    compare(s.navi.chosen.length, 1)
    compare(s.navi.chosen[0].name, "beta-1")
    verify(s.navi.chosen[0] === s.app.projects.projects[1], "the entry object itself")
  }

  // 9: a pin — the row's own click is unchanged, so this passes before the
  // button has a click handler.
  function test_a_row_click_still_opens_any_projects_run() {
    var s = make(twoProjects()); if (!s) return
    s.runs.project = "/home/u/a"
    s.nav.cursorIndex = 2
    wait(20)
    compare(openButton(s, 2).visible, true)
    tap(H.find(s.screen, "runRowTitle2"))
    compare(s.navi.opened, "run-b-live0003")
    compare(s.navi.chosen.length, 0)
  }

  // Review Focus 5.
  function test_open_project_under_a_project_filter_leaves_the_filter_alone() {
    var s = make(twoProjects()); if (!s) return
    s.runs.project = "/home/u/a"
    s.runs.toggleProjectFilter("/home/u/b")
    s.runs.projectToggles = []
    s.nav.cursorIndex = 0
    wait(20)
    compare(H.find(s.screen, "runRowId0").text, "…live0003", "beta's run, flat")
    tap(openButton(s, 0))
    compare(s.navi.chosen.length, 1)
    compare(s.navi.chosen[0].root_path, "/home/u/b")
    compare(s.runs.projectToggles.length, 0)
    compare(s.runs.projectFilter, "/home/u/b")
  }
}
