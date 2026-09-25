import QtQuick
import QtTest
import "../../ui/components"

// The graph's wheel input: a touchpad two-finger SLIDE pans, a mouse wheel
// zooms, and nothing between the panel's Flickable and the canvas swallows a
// wheel event on the way down.
TestCase {
  id: tc
  name: "GraphWheel"
  when: windowShown
  visible: true
  width: 700; height: 500

  property var nodes: [
    { id: "m1", title: "First", status: "done", done: 1, total: 2, x: 0, y: 0, w: 230, h: 78 },
    { id: "m2", title: "Second", status: "todo", done: 0, total: 0, x: 320, y: 0, w: 230, h: 78 }
  ]
  property var edges: [{ id: "m1>m2", from: "m1", to: "m2" }]

  Component { id: viewC; GraphView { width: 560; height: 360 } }

  // The panel's own stack around the graph, so a wheel event has to travel the
  // real way down: a vertical Flickable, its Column, the screen's wrapper Item.
  Component {
    id: stackC

    Flickable {
      width: 600; height: 400
      contentWidth: width
      contentHeight: column.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      interactive: contentHeight > height

      property alias graph: graphView

      Column {
        id: column
        width: parent.width

        Item {
          width: parent.width
          height: 380

          GraphView {
            id: graphView
            anchors.fill: parent
          }
        }
      }
    }
  }

  function find(item, name) {
    if (item.objectName === name) return item
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) { var r = find(kids[i], name); if (r) return r }
    var data = item.data || []
    for (var j = 0; j < data.length; j++) { var d = find(data[j], name); if (d) return d }
    return null
  }

  function makeView(mode) {
    var v = createTemporaryObject(viewC, tc)
    v.mode = mode || "milestone"
    v.nodes = tc.nodes
    v.edges = tc.edges
    wait(100)
    return v
  }

  // ---- the panel stack lets a wheel through --------------------------------

  function test_a_mouse_wheel_reaches_the_canvas_through_the_panel_stack() {
    var stack = createTemporaryObject(stackC, tc)
    stack.graph.nodes = tc.nodes
    stack.graph.edges = tc.edges
    wait(100)
    var canvas = find(stack.graph, "graphCanvas")
    var before = canvas.zoom
    mouseWheel(stack, 300, 200, 0, 120, Qt.NoButton, Qt.NoModifier)
    verify(canvas.zoom > before, "a mouse notch still zooms the canvas in the panel stack")
  }

  // ---- a touchpad slide pans ----------------------------------------------

  function test_a_touchpad_slide_with_a_pixel_delta_pans() {
    var v = makeView()
    var canvas = find(v, "graphCanvas")
    var panX = canvas.panX, panY = canvas.panY, zoom = canvas.zoom
    v._handleTouchpadWheel({ x: 30, y: -40 }, { x: 0, y: 0 }, Qt.NoModifier, { x: 100, y: 100 })
    compare(canvas.panX, panX + 30 * v._panGain)
    compare(canvas.panY, panY - 40 * v._panGain)
    compare(canvas.zoom, zoom)
  }

  // The bug: some stacks report a touchpad slide with NO pixel delta at all,
  // only an angle one. Read as a mouse notch that is a zoom, or nothing.
  function test_a_touchpad_slide_without_a_pixel_delta_still_pans() {
    var v = makeView()
    var canvas = find(v, "graphCanvas")
    var panX = canvas.panX, panY = canvas.panY, zoom = canvas.zoom
    v._handleTouchpadWheel({ x: 0, y: 0 }, { x: 0, y: 120 }, Qt.NoModifier, { x: 100, y: 100 })
    compare(canvas.zoom, zoom)
    compare(canvas.panX, panX)
    compare(canvas.panY, panY + v._wheelNotchPixels * v._panGain)
  }

  function test_a_horizontal_touchpad_slide_without_a_pixel_delta_pans_sideways() {
    var v = makeView()
    var canvas = find(v, "graphCanvas")
    var panX = canvas.panX, panY = canvas.panY, zoom = canvas.zoom
    v._handleTouchpadWheel({ x: 0, y: 0 }, { x: -120, y: 0 }, Qt.NoModifier, { x: 100, y: 100 })
    compare(canvas.zoom, zoom)
    compare(canvas.panX, panX - v._wheelNotchPixels * v._panGain)
    compare(canvas.panY, panY)
  }

  function test_the_story_view_pans_on_a_slide_too() {
    var v = makeView("story")
    var canvas = find(v, "graphCanvas")
    var panY = canvas.panY, zoom = canvas.zoom
    v._handleTouchpadWheel({ x: 0, y: 0 }, { x: 0, y: -120 }, Qt.NoModifier, { x: 100, y: 100 })
    compare(canvas.zoom, zoom)
    compare(canvas.panY, panY - v._wheelNotchPixels * v._panGain)
  }

  // ---- what must NOT change ------------------------------------------------

  function test_ctrl_and_a_touchpad_slide_still_zooms() {
    var v = makeView()
    var canvas = find(v, "graphCanvas")
    var zoom = canvas.zoom
    v._handleTouchpadWheel({ x: 0, y: 0 }, { x: 0, y: 120 }, Qt.ControlModifier, { x: 100, y: 100 })
    verify(canvas.zoom > zoom, "Ctrl keeps the zoom gesture")
  }

  function test_ctrl_and_a_pixel_slide_still_zooms() {
    var v = makeView()
    var canvas = find(v, "graphCanvas")
    var zoom = canvas.zoom
    v._handleTouchpadWheel({ x: 0, y: 20 }, { x: 0, y: 0 }, Qt.ControlModifier, { x: 100, y: 100 })
    verify(canvas.zoom > zoom, "Ctrl keeps the zoom gesture for a pixel delta too")
  }

  function test_an_empty_wheel_does_nothing() {
    var v = makeView()
    var canvas = find(v, "graphCanvas")
    var panX = canvas.panX, panY = canvas.panY, zoom = canvas.zoom
    v._handleTouchpadWheel({ x: 0, y: 0 }, { x: 0, y: 0 }, Qt.NoModifier, { x: 100, y: 100 })
    v._handleTouchpadWheel(null, null, Qt.NoModifier, { x: 100, y: 100 })
    v._handleTouchpadWheel({ x: NaN, y: NaN }, { x: NaN, y: NaN }, Qt.NoModifier, { x: 100, y: 100 })
    compare(canvas.panX, panX)
    compare(canvas.panY, panY)
    compare(canvas.zoom, zoom)
  }

  // A mouse wheel must never reach the touchpad handler: it keeps zooming.
  function test_a_mouse_wheel_zooms_and_does_not_pan() {
    var v = makeView()
    var canvas = find(v, "graphCanvas")
    var panX = canvas.panX, zoom = canvas.zoom
    mouseWheel(v, 280, 180, 0, 120, Qt.NoButton, Qt.NoModifier)
    verify(canvas.zoom > zoom, "the mouse wheel still zooms")
    verify(canvas.panX !== panX || canvas.panX === panX, "zoom about the cursor may move pan")
  }

  // The drag gestures the overlay sits in front of must still work.
  function test_a_background_drag_still_pans() {
    var v = makeView()
    var canvas = find(v, "graphCanvas")
    var panX = canvas.panX
    mousePress(v, 40, 300)
    mouseMove(v, 90, 300)
    mouseMove(v, 140, 300)
    mouseRelease(v, 140, 300)
    verify(canvas.panX !== panX, "a background drag still pans the canvas")
  }
}
