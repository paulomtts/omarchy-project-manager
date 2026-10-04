// tests/ui/screens/tst_runs_screen.qml
// ui/screens/RunsScreen.qml on its own: the rows it renders, the chips, the
// footer and banners, and the empty and missing states. A stub app: a REAL
// NavigationStore, plus a plain object carrying the RunStore properties the
// screen reads (the real store's `watching` is a read-only alias that cannot
// be set from a test), filtered through the same domain functions the store
// uses. The navigator is a recorder.
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
      readonly property var filteredRuns: Runs.searchRuns(Runs.filterRuns(rs.runs, rs.runFilter), rs.searchQuery)
      function toggleRunFilter(id) { rs.runFilter = id === "all" || id === rs.runFilter ? "" : id }
    }
  }

  Component {
    id: appC
    QtObject {
      property var nav: null
      property var runs: null
      property var projects: ({ selectedProject: { root_path: "/home/u/a", name: "alpha" } })
    }
  }

  Component {
    id: naviC
    QtObject {
      property string opened: ""
      property int hovered: -1
      function openRun(id) { opened = String(id) }
      function hoverCursor(index) { hovered = index }
    }
  }

  function make(list) {
    var host = createTemporaryObject(hostC, tc)
    var navComp = Qt.createComponent("../../../core/stores/NavigationStore.qml")
    if (navComp.status !== Component.Ready) { fail(navComp.errorString()); return null }
    var nav = navComp.createObject(host)
    var runs = runsC.createObject(host)
    runs.searchQuery = Qt.binding(function() { return nav.searchQuery })
    var app = appC.createObject(host, { nav: nav, runs: runs })
    var navi = naviC.createObject(host)
    var sC = Qt.createComponent("../../../ui/screens/RunsScreen.qml")
    if (sC.status !== Component.Ready) { fail(sC.errorString()); return null }
    var screen = sC.createObject(host, { width: 500, app: app, navigator: navi })
    nav.viewMode = "runs"
    runs.runs = list || []
    wait(20)
    return { app: app, runs: runs, nav: nav, navi: navi, screen: screen }
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
  function sample() {
    return [
      run("run-20261004-live0001", "started", true, { milestone: "alpha", started_at: ago(5 * tc.minute), tree: { stories: [], subtasks: [
        { card_id: "t1", phases: [{ name: "spec", status: "done" }] },
        { card_id: "t2", phases: [{ name: "spec", status: "done" }, { name: "implement", status: "started" }] }] } }),
      run("run-20261004-escl0002", "escalated", null, { milestone: "beta", tree: { stories: [], subtasks: [
        { card_id: "t3", phases: [{ name: "review", status: "failed", detail: "tests red after 3 attempts" }] }] } }),
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

  function test_a_row_shows_short_id_title_progress_phase_and_age() {
    var s = make(sample()); if (!s) return
    compare(H.find(s.screen, "runRowId0").text, "…live0001")
    compare(H.find(s.screen, "runRowTitle0").text, "alpha")
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

  // ---- empty and missing

  function test_no_runs_says_so() {
    var s = make([]); if (!s) return
    var msg = H.find(s.screen, "runsMessage")
    compare(msg.text, "No runs for this project yet.")
    compare(msg.visible, true)
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
    compare(footer.text, "am · schema 1 · watching")
    compare(footer.visible, true)
    s.runs.watching = false
    compare(footer.text, "am · schema 1 · not watching")
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
    compare(s.screen.visible, false)
  }
}
