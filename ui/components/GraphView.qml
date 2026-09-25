import QtQuick
import Quickshell
import qs.Commons
import "../../vendor/canvas" as Local
import "../../vendor/canvas/positions.js" as Positions
import "../../core/domain/board.js" as Board
import "../../core/domain/graph.js" as Graph
import "../components" as UI
import "../theme" as T

// The Graph section on a pan/zoom canvas, in either of its two views: one node
// per milestone, or one per story with a labelled box around each milestone's
// own. It renders and emits only; the store owns the model and the cursor.
Item {
  id: view
  objectName: "graphView"

  property var nodes: []
  property var edges: []
  // "milestone" or "story": which delegate the nodes take, and whether the
  // boxes below are drawn at all.
  property string mode: "milestone"
  // [{ id, title }] -- the story view's milestone boxes, empty in the milestone
  // view. Where a box IS is not taken from the model: it is derived below from
  // the stories it holds, wherever they currently are.
  property var groups: []
  // [{ id, from, to }] between two of those boxes: the milestone-level reading
  // of the story view, empty in the milestone view.
  property var groupEdges: []
  property string cursorId: ""
  // ---- am run marks (5.3), handed in by GraphScreen, which reads the run
  // store: this view has no `app`. By card id -- runMarks: Runs.cardRunState,
  // runRollups: Runs.rollup -- plus the subtask pips to ring and whether the run
  // data is stale (drawn dimmed). A missing or inherited id draws nothing.
  property var runMarks: ({})
  property var runRollups: ({})
  property var runRinged: []
  property bool runStale: false

  function _ownValue(map, id) {
    return map !== null && map !== undefined && typeof map === "object" && !Array.isArray(map)
      && typeof id === "string" && id !== "" && Object.prototype.hasOwnProperty.call(map, id) ? map[id] : null
  }
  function runMarkOf(id) { return view._ownValue(view.runMarks, id) }
  function runRollupOf(id) { return view._ownValue(view.runRollups, id) }
  // The one input for every colour and font: Panel passes its Theme down,
  // and a standalone instance renders with the shell defaults.
  property var theme: T.Theme {}

  signal nodeClicked(string id)

  function centerOn(id) { canvas.centerOn(id) }

  // ---- Where things are -----------------------------------------------------
  //
  // The user's own arrangement: the position a story was dropped at, or moved
  // to with its whole box, by card id. It overrides what the layout decided.
  // A board change hands this view a new `nodes` array and clears it, so a
  // refresh resets an arranged story graph exactly as it resets a dragged node
  // in the milestone view -- one behaviour, both views.
  property var arranged: ({})
  onNodesChanged: view.arranged = ({})

  // What the canvas is actually given: the nodes at their arranged positions.
  // The canvas treats a node's coordinates as pinned, so this is what makes an
  // arrangement outlive a model rebuild the canvas does for its own reasons.
  readonly property var placedNodes: Graph.placedNodes(view.nodes, view.arranged)

  // Where every node IS right now, by card id -- a node halfway through a drag
  // included, because the canvas's working positions are what it draws from.
  // Read-only, and the one place this view reads the canvas's own bookkeeping
  // (documented exception, docs/architecture.md).
  readonly property var livePositions: {
    var out = ({})
    var live = canvas._positions || ({})
    ;(view.nodes || []).forEach(function(node) {
      var at = live[Positions.key(node.id)]
      if (at) out[node.id] = { x: at.x, y: at.y }
    })
    return out
  }

  // The boxes as they are now: each milestone's own stories' bounding box, so a
  // story can never be outside its box, however it was dragged. Membership is
  // the story's milestone and nothing else -- a story dropped over another
  // milestone's box is not adopted by it.
  readonly property var liveGroups: Graph.storyGroupRects(view.groups, view.nodes, view.livePositions)

  // The same boxes as the canvas edge layer wants them: by its own key, each
  // rect carrying both the anchor ({x, y}) and the size ({w, h}).
  readonly property var boxByKey: {
    var out = ({})
    ;(view.liveGroups || []).forEach(function(box) { out[Positions.key(box.id)] = box })
    return out
  }
  readonly property var boxKeys: (view.liveGroups || []).map(function(box) { return Positions.key(box.id) })

  // One frame of a box move: the stories it holds are moved in the canvas's own
  // working positions, so the boxes, the box edges and the nodes all follow the
  // pointer WITHOUT a new nodes array -- which would lay the whole graph out
  // again, on every pointer event.
  function moveGroupLive(id, dx, dy) {
    var moved = Graph.moveGroupPositions(view.nodes, id, dx, dy, view.livePositions)
    ;(view.nodes || []).forEach(function(node) {
      if (node.milestoneId === id) canvas._moveNode(node.id, moved[node.id])
    })
  }

  // The end of a box move: where its stories ended up becomes the arrangement,
  // once, so it survives the next model rebuild like any dropped node.
  function commitGroup(id) {
    view.arranged = Graph.adoptGroupPositions(view.nodes, id, view.arranged, view.livePositions)
  }

  // Moving a whole box by a world delta, frames and commit in one: every story
  // it holds moves with it, and nothing else does.
  function moveGroup(id, dx, dy) {
    view.moveGroupLive(id, dx, dy)
    view.commitGroup(id)
  }

  // The organize button. In the story view the model's own layout already puts
  // every story inside its own box and keeps the boxes apart, so organizing is
  // dropping the arrangement and going back to it -- a fresh (empty) map is
  // assigned even when there was none, so the canvas re-reads the model and a
  // dragged story returns too.
  function organize() {
    if (view.mode !== "story") { canvas.organize(); return }
    view.arranged = ({})
    Qt.callLater(view.fitAll)
  }

  // Frame the whole graph. The canvas only knows its nodes, so in the story
  // view the boxes -- which reach past their stories by their padding and their
  // label strip -- are added here and the union is what gets framed.
  function fitAll() {
    var rect = view.contentBounds()
    if (rect === null) { canvas.fitAll(); return }
    canvas.fitBounds(rect)
  }

  // The union of every node and every box, in world coordinates, or null when
  // there is nothing (or nothing measurable) to frame.
  function contentBounds() {
    var boxes = (view.mode === "story" ? view.liveGroups : []) || []
    if (boxes.length === 0) return null
    var rect = null
    function add(item) {
      if (!item || !isFinite(item.x) || !isFinite(item.y) || !(item.w > 0) || !(item.h > 0)) return
      if (rect === null) { rect = { x: item.x, y: item.y, w: item.w, h: item.h }; return }
      var right = Math.max(rect.x + rect.w, item.x + item.w)
      var bottom = Math.max(rect.y + rect.h, item.y + item.h)
      rect.x = Math.min(rect.x, item.x)
      rect.y = Math.min(rect.y, item.y)
      rect.w = right - rect.x
      rect.h = bottom - rect.y
    }
    boxes.forEach(add)
    // At their live positions: a dragged story is inside its box anyway, and a
    // stale model coordinate would frame emptiness.
    Graph.placedNodes(view.nodes, view.livePositions).forEach(add)
    return rect
  }

  // ---- Touchpad wheel -------------------------------------------------------
  //
  // Two fingers moving APART zoom (the canvas's PinchHandler, untouched); two
  // fingers moving TOGETHER must pan. The canvas's own wheel entry point
  // already pans when the event carries a pixel delta -- but a touchpad slide
  // does not always arrive that way: Qt on Wayland may report it with an angle
  // delta only, which that entry point reads as a mouse notch, and a slide then
  // zooms (or, when the notch is horizontal, does nothing at all).
  //
  // So touchpad wheels are taken HERE, in front of the canvas, normalised to a
  // pixel delta, and handed to the canvas's one wheel entry point -- no camera
  // arithmetic is reimplemented. A WheelHandler that fires blocks the items
  // behind it, so the canvas never sees the same event twice; and mouse wheels
  // never reach this handler at all (acceptedDevices), so wheel-zoom and
  // Ctrl+wheel are exactly what they were.

  // One mouse notch is 120 angle units; this is what a notch is worth in pixels
  // when a touchpad slide reports no pixel delta of its own. A tuning constant.
  readonly property real _wheelNotchPixels: 50

  // How far the canvas moves per pixel of touchpad slide, applied to either
  // source above. 1 = the content tracks the fingers exactly; higher is
  // more sensitive. A tuning constant.
  readonly property real _panGain: 1.8

  // The pan delta a touchpad wheel asks for: its own pixel delta when it has a
  // usable one, else its angle delta at _wheelNotchPixels per notch. Both carry
  // the same sign convention (positive = up / away), so the fallback pans the
  // way the pixel delta would. Non-finite fields count as zero.
  function _touchpadPixels(pixelDelta, angleDelta) {
    function number(value) { return (typeof value === "number" && isFinite(value)) ? value : 0 }
    var px = number(pixelDelta ? pixelDelta.x : 0)
    var py = number(pixelDelta ? pixelDelta.y : 0)
    if (px !== 0 || py !== 0) return { x: px, y: py }
    var ax = number(angleDelta ? angleDelta.x : 0)
    var ay = number(angleDelta ? angleDelta.y : 0)
    return { x: ax / 120 * view._wheelNotchPixels, y: ay / 120 * view._wheelNotchPixels }
  }

  // A whole touchpad wheel event. Ctrl is the zoom modifier and is forwarded
  // untouched, so Ctrl+slide still zooms about the cursor exactly as before;
  // everything else becomes a pan. An event that asks for nothing is dropped
  // rather than forwarded, so a stray zero can never be read as a notch.
  function _handleTouchpadWheel(pixelDelta, angleDelta, modifiers, point) {
    if ((modifiers & Qt.ControlModifier) !== 0) {
      canvas._handleWheel(pixelDelta, angleDelta, modifiers, point)
      return
    }
    var delta = view._touchpadPixels(pixelDelta, angleDelta)
    if (delta.x === 0 && delta.y === 0) return
    canvas._handleWheel({ x: delta.x * view._panGain, y: delta.y * view._panGain },
                        { x: 0, y: 0 }, Qt.NoModifier, point)
  }

  // Opt-in tracing of every wheel event that reaches the graph, so the shape a
  // real device delivers can be read off the shell log. Run the shell with
  // OPM_DEBUG_WHEEL=1 (see README) -- off, nothing below runs.
  readonly property bool _debugWheel: view._envIsOne("OPM_DEBUG_WHEEL")

  // An unset variable reads back as undefined, and a host that cannot answer at
  // all must not take the graph down with it: anything but "1" means off.
  function _envIsOne(name) {
    try { return ("" + Quickshell.env(name)) === "1" } catch (error) { return false }
  }

  function _logWheel(where, event) {
    var device = event.device
    console.log("[opm wheel] " + where
                + " device=" + (device ? device.type : "?")
                + " name=" + (device ? device.name : "?")
                + " pixelDelta=" + event.pixelDelta.x + "," + event.pixelDelta.y
                + " angleDelta=" + event.angleDelta.x + "," + event.angleDelta.y
                + " phase=" + event.phase
                + " modifiers=" + event.modifiers
                + " inverted=" + event.inverted)
  }

  Local.Canvas {
    id: canvas
    objectName: "graphCanvas"
    anchors.fill: parent
    nodes: view.mode === "story" ? view.placedNodes : view.nodes
    edges: view.edges
    nodeDelegate: view.mode === "story" ? storyDelegate : milestoneDelegate
    // A dropped story keeps its place: the arrangement is this view's, so the
    // canvas is handed the new coordinates rather than owning them alone.
    onNodeMoved: function(id, x, y) {
      if (view.mode === "story") view.arranged = Graph.withPosition(view.arranged, id, x, y)
    }
    // Read-only board: the canvas may drag nodes around, but never draws a
    // dependency of its own.
    canConnect: function() { return false }
    onNodeClicked: function(id) { view.nodeClicked(id) }
    onWidthChanged: Qt.callLater(view.fitAll)
    Component.onCompleted: Qt.callLater(view.fitAll)

    // The story view's milestone boxes. The canvas draws nodes and edges only,
    // so this layer sits inside it, applies the very same camera, and is pushed
    // behind the canvas's own world item -- the boxes must never cover a node.
    Item {
      id: groupLayer
      objectName: "graphGroupLayer"
      z: -1
      visible: view.mode === "story"
      x: canvas.panX
      y: canvas.panY
      scale: canvas.zoom
      transformOrigin: Item.TopLeft

      // The dependency BETWEEN the boxes, the canvas's own edge layer drawing
      // it: one curve from a box's right border to the next box's left border,
      // exactly as the milestone view draws a milestone's. Declared first, so
      // it paints behind the boxes and their stories, and thicker and fainter
      // than a story edge so the two are never confused. No hit width: a box
      // edge is not clickable, and must not swallow a pan.
      Local.CanvasEdges {
        objectName: "graphGroupEdges"
        edges: view.mode === "story" ? view.groupEdges : []
        // The box rects serve as both: {x, y} to anchor on, {w, h} to size.
        positions: view.boxByKey
        nodeByKey: view.boxByKey
        visibleKeys: view.boxKeys
        strokeColor: Qt.alpha(view.theme.foreground, 0.22)
        strokeWidth: 5
        hitWidth: 0
      }

      // The model is the STABLE list of groups, never the live rects: a drag
      // recomputes those on every pointer move, and a Repeater told its model
      // changed rebuilds its delegates -- which would destroy the very handler
      // driving the gesture. Each box looks its own rect up instead, so the
      // geometry follows without the item ever being replaced.
      Repeater {
        model: view.groups

        delegate: Rectangle {
          id: box
          required property var modelData

          readonly property string boxId: box.modelData ? box.modelData.id : ""
          readonly property var rect: view.boxByKey[Positions.key(box.boxId)]

          objectName: "graphGroup" + box.boxId
          // A group whose stories are all gone has no rect, and no box.
          visible: !!box.rect
          x: box.rect ? box.rect.x : 0
          y: box.rect ? box.rect.y : 0
          width: box.rect ? box.rect.w : 0
          height: box.rect ? box.rect.h : 0
          radius: 12
          color: Qt.alpha(view.theme.foreground, 0.04)
          border.width: 1
          border.color: Qt.alpha(view.theme.foreground, 0.18)

          // The label strip drags the whole box. Only the strip: the rest of a
          // box is either a story (which drags itself) or empty space, where a
          // drag has to stay the canvas's pan.
          Item {
            id: handle
            objectName: "graphGroupHandle" + box.boxId
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: Graph.GROUP_HEADER

            DragHandler {
              id: boxDrag
              target: null

              // A SCENE point in world coordinates. The layer carries the
              // camera but not this box, so the mapping holds still while the
              // box follows the drag -- read in the box's own frame, every
              // frame after the first would measure nothing.
              function world(scenePoint) {
                return groupLayer.mapFromItem(null, scenePoint.x, scenePoint.y)
              }

              property var last: null
              // The gesture starts at the PRESS, not where the drag threshold
              // was crossed, so the box lands exactly where the pointer took
              // it; and it is committed ONCE, when it ends (a release or a
              // cancelled grab both end it), because the frames below moved the
              // stories in the canvas's working positions only.
              onActiveChanged: {
                if (boxDrag.active) {
                  boxDrag.last = boxDrag.world(centroid.scenePressPosition)
                  return
                }
                boxDrag.last = null
                view.commitGroup(box.boxId)
              }
              onCentroidChanged: {
                if (!boxDrag.active || !boxDrag.last) return
                var now = boxDrag.world(centroid.scenePosition)
                view.moveGroupLive(box.boxId, now.x - boxDrag.last.x, now.y - boxDrag.last.y)
                boxDrag.last = now
              }
            }
          }

          UI.ThemedText {
            objectName: "graphGroupLabel" + (box.modelData ? box.modelData.id : "")
            variant: "caption"
            theme: view.theme
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.leftMargin: 10
            anchors.topMargin: 6
            anchors.right: parent.right
            anchors.rightMargin: 10
            text: box.modelData ? box.modelData.title : ""
            font.bold: true
            elide: Text.ElideRight
          }
        }
      }
    }
  }

  // The wheel layer, in front of the canvas and behind nothing that matters: it
  // carries wheel handlers ONLY, so presses, drags, taps and the pinch all fall
  // straight through to the canvas and its nodes, boxes and controls.
  Item {
    id: wheelLayer
    objectName: "graphWheelLayer"
    anchors.fill: parent

    // Touchpad only. It blocks (the default), so the canvas's own wheel
    // handler never sees the event -- this one has already forwarded it.
    WheelHandler {
      objectName: "graphTouchpadWheelHandler"
      target: null
      acceptedDevices: PointerDevice.TouchPad

      onWheel: function(event) {
        if (view._debugWheel) view._logWheel("touchpad", event)
        var at = canvas.mapFromItem(wheelLayer, event.x, event.y)
        view._handleTouchpadWheel(event.pixelDelta, event.angleDelta, event.modifiers,
                                  { x: at.x, y: at.y })
      }
    }

    // Tracing only, for every device: `blocking: false` so it never takes an
    // event away from the handler above or from the canvas, and `enabled` so
    // nothing of it runs unless OPM_DEBUG_WHEEL=1 asked for it.
    WheelHandler {
      objectName: "graphWheelLogHandler"
      target: null
      enabled: view._debugWheel
      blocking: false
      onWheel: function(event) { view._logWheel("seen", event) }
    }
  }

  // Live refreshes replace the model every time the board changes; only a
  // different set of milestones (or showing the view again) reframes it, so a
  // pan/zoom survives an unrelated edit.
  readonly property string idKey: nodes.map(function(n) { return n.id }).join("|")
  onIdKeyChanged: Qt.callLater(view.fitAll)
  onVisibleChanged: if (visible) Qt.callLater(view.fitAll)

  // The vendored controls drive a canvas; here they drive the VIEW where the
  // view knows more than the canvas does -- organizing a story graph is per
  // box, and framing it has to take the boxes in. Zoom and culling are the
  // canvas's own.
  QtObject {
    id: controlsTarget
    readonly property bool culling: canvas.culling
    function zoomBy(factor) { canvas.zoomBy(factor) }
    function fitAll() { view.fitAll() }
    function organize() { view.organize() }
  }

  Local.CanvasControls { canvas: controlsTarget; showCulling: false }

  UI.ThemedText {
    objectName: "graphEmpty"
    variant: "dim"
    theme: view.theme
    anchors.centerIn: parent
    visible: view.nodes.length === 0
    text: view.mode === "story" ? "No stories in this project." : "No milestones in this project."
  }

  Component {
    id: milestoneDelegate

    Rectangle {
      id: node
      // The canvas's Loader clears modelData while it tears a node down.
      readonly property var entry: modelData ? modelData : ({ id: "", title: "", status: "", done: 0, total: 0, openIssues: 0 })
      readonly property bool current: entry.id !== "" && view.cursorId === entry.id
      readonly property color tint: Board.statusColor(entry.status, view.theme.dim)
      objectName: "graphNode" + entry.id
      implicitWidth: Graph.GRAPH_NODE_W
      implicitHeight: Graph.GRAPH_NODE_H
      radius: 8
      color: Qt.alpha(view.theme.foreground, current ? 0.14 : 0.06)
      border.width: current ? 2 : 1
      border.color: current ? view.theme.foreground : Qt.alpha(view.theme.foreground, 0.25)

      Rectangle {
        width: 5
        height: parent.height - 2 * node.radius
        anchors.left: parent.left
        anchors.leftMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        radius: 2
        color: node.tint
      }

      Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 20
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        Item {
          width: parent.width
          height: Math.max(nodeTitle.implicitHeight, nodeRunMark.shown ? nodeRunMark.height : 0)

          UI.ThemedText {
            id: nodeTitle
            objectName: "graphNodeTitle"
            theme: view.theme
            anchors.left: parent.left
            anchors.right: nodeRunMark.shown ? nodeRunMark.left : parent.right
            anchors.rightMargin: nodeRunMark.shown ? 6 : 0
            anchors.verticalCenter: parent.verticalCenter
            text: node.entry.title
            font.bold: true
            elide: Text.ElideRight
          }

          UI.RunMark {
            id: nodeRunMark
            theme: view.theme
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            runState: view.runMarkOf(node.entry.id)
            rollup: view.runRollupOf(node.entry.id)
            stale: view.runStale
            active: view.visible
          }
        }

        Item {
          width: parent.width
          height: progress.implicitHeight

          UI.ThemedText {
            id: progress
            objectName: "graphNodeProgress"
            variant: "caption"
            theme: view.theme
            anchors.left: parent.left
            anchors.right: issues.visible ? issues.left : parent.right
            anchors.rightMargin: issues.visible ? 6 : 0
            text: node.entry.total > 0 ? node.entry.done + "/" + node.entry.total + " done" : "No stories"
            elide: Text.ElideRight
          }

          // Open issues blocking this milestone; closed ones add nothing.
          UI.ThemedText {
            id: issues
            objectName: "graphNodeIssues"
            variant: "caption"
            theme: view.theme
            anchors.right: parent.right
            visible: (node.entry.openIssues || 0) > 0
            text: "\uF024 " + Graph.openIssueLabel(node.entry.openIssues || 0)
            color: Board.statusColor("blocked", view.theme.dim)
          }
        }

        // The milestone's am run rollup; hides itself without one.
        UI.RunRollupBar {
          theme: view.theme
          rollup: view.runRollupOf(node.entry.id)
          opacity: nodeRunMark.dimmed ? 0.5 : 1
        }
      }
    }
  }

  // A story node: the same frame, status stripe and open-issue flag as a
  // milestone, with one pip per subtask where the milestone shows done/total.
  Component {
    id: storyDelegate

    Rectangle {
      id: storyNode
      readonly property var entry: modelData ? modelData
        : ({ id: "", title: "", status: "", openIssues: 0, pips: [], morePips: 0 })
      readonly property bool current: entry.id !== "" && view.cursorId === entry.id
      readonly property color tint: Board.statusColor(entry.status, view.theme.dim)
      objectName: "graphNode" + entry.id
      implicitWidth: Graph.STORY_NODE_W
      implicitHeight: Graph.STORY_NODE_H
      radius: 8
      color: Qt.alpha(view.theme.foreground, current ? 0.14 : 0.06)
      border.width: current ? 2 : 1
      border.color: current ? view.theme.foreground : Qt.alpha(view.theme.foreground, 0.25)

      Rectangle {
        width: 5
        height: parent.height - 2 * storyNode.radius
        anchors.left: parent.left
        anchors.leftMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        radius: 2
        color: storyNode.tint
      }

      Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 20
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        Item {
          width: parent.width
          height: Math.max(storyTitle.implicitHeight, storyRunMark.shown ? storyRunMark.height : 0)

          UI.ThemedText {
            id: storyTitle
            objectName: "graphNodeTitle"
            theme: view.theme
            anchors.left: parent.left
            anchors.right: storyRunMark.shown ? storyRunMark.left : parent.right
            anchors.rightMargin: storyRunMark.shown ? 6 : 0
            anchors.verticalCenter: parent.verticalCenter
            text: storyNode.entry.title
            font.bold: true
            elide: Text.ElideRight
          }

          UI.RunMark {
            id: storyRunMark
            theme: view.theme
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            runState: view.runMarkOf(storyNode.entry.id)
            rollup: view.runRollupOf(storyNode.entry.id)
            stale: view.runStale
            active: view.visible
          }
        }

        Item {
          width: parent.width
          height: Math.max(pips.implicitHeight, storyIssues.implicitHeight)

          UI.StatusPips {
            id: pips
            objectName: "graphNodePips"
            theme: view.theme
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            model: storyNode.entry.pips || []
            more: storyNode.entry.morePips || 0
            // The subtasks an am run is working on right now.
            ringedIds: view.runRinged
            // The section hides the whole view; a delegate inside the canvas is
            // not always told, so the verdict is handed down explicitly and the
            // pulse never runs for a graph nobody is looking at.
            active: view.visible
          }

          UI.ThemedText {
            id: storyIssues
            objectName: "graphNodeIssues"
            variant: "caption"
            theme: view.theme
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: (storyNode.entry.openIssues || 0) > 0
            text: "\uF024 " + Graph.openIssueLabel(storyNode.entry.openIssues || 0)
            color: Board.statusColor("blocked", view.theme.dim)
          }
        }

        // The story's am run rollup; hides itself without one.
        UI.RunRollupBar {
          theme: view.theme
          rollup: view.runRollupOf(storyNode.entry.id)
          opacity: storyRunMark.dimmed ? 0.5 : 1
        }
      }
    }
  }
}
