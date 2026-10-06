import QtQuick
import qs.Commons
import "../../core/domain/board.js" as Board
import "../../core/domain/runs.js" as Runs
import "../components" as UI
import "../theme" as T

// The Graph section: the shared GraphView, fed from the graph store. The
// wrapper exists so the panel can keep reaching the view (it centres the
// canvas on the keyboard cursor) without reaching into the screen's markup.
Item {
  id: graphScreen

  property var app
  property var navigator
  property var theme: T.Theme {}

  // The height of the panel's Flickable: the graph takes whatever is left of it
  // below its own y, exactly as the view did when it sat in the panel directly.
  property real viewportHeight: 0

  // Panel's `centerOnGraphNode` action drives the canvas through this.
  readonly property var graphView: view

  visible: graphScreen.app.nav.viewMode === "graph" && !!graphScreen.app.projects.selectedProject
  height: Math.max(Style.space(240), graphScreen.viewportHeight - graphScreen.y - Style.space(12))

  // ---- am run marks (5.3): computed here from the run store and handed to the
  // view, which has no `app`. A merged or canceled node (or archived, should
  // brd ever report it) gets none -- a visibility rule only, never a run state
  // -- and no node gets any while am is not installed. Maps by card id with no
  // prototype, so any card id is just a key.
  readonly property var runMarkData: graphScreen.buildRunMarks(graphScreen.app.graph.currentNodes,
                                                               graphScreen.app.runs.runs, graphScreen.app.runs.amStatus)

  function hidesRunMarks(status) {
    return Board.isClosedStatus(status)
  }

  // { marks: id -> Runs.cardRunState, rollups: id -> Runs.rollup, ringed: [pip id] }.
  // A pip is ringed when its run is live and running AND its own subtask status is in the
  // running bucket: the subtask am is working on now, not every subtask of the run.
  function buildRunMarks(nodes, runs, amStatus) {
    var marks = Object.create(null)
    var rollups = Object.create(null)
    var ringed = []
    var out = { marks: marks, rollups: rollups, ringed: ringed }
    if (amStatus === "missing" || !Array.isArray(nodes)) return out
    for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i]
      if (!node || typeof node.id !== "string" || graphScreen.hidesRunMarks(node.status)) continue
      marks[node.id] = Runs.cardRunState(runs, node.id)
      rollups[node.id] = Runs.rollup(runs, { id: node.id })
      var pips = Array.isArray(node.pips) ? node.pips : []
      for (var j = 0; j < pips.length; j++) {
        var pip = pips[j]
        if (!pip || typeof pip.id !== "string" || graphScreen.hidesRunMarks(pip.status)) continue
        if (Runs.cardRunState(runs, pip.id).state === "running" && Runs.rollup(runs, { id: pip.id }).running > 0)
          ringed.push(pip.id)
      }
    }
    return out
  }

  UI.GraphView {
    id: view
    anchors.fill: parent
    nodes: graphScreen.app.graph.currentNodes
    edges: graphScreen.app.graph.currentEdges
    groups: graphScreen.app.graph.currentGroups
    groupEdges: graphScreen.app.graph.currentGroupEdges
    mode: graphScreen.app.graph.graphView
    cursorId: graphScreen.app.graph.graphCursor
    theme: graphScreen.theme
    runMarks: graphScreen.runMarkData.marks
    runRollups: graphScreen.runMarkData.rollups
    runRinged: graphScreen.runMarkData.ringed
    runStale: graphScreen.app.runs.stale
    onNodeClicked: function(id) { graphScreen.app.graph.graphCursor = id; graphScreen.navigator.openCard(id) }
  }
}
