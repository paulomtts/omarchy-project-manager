import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "runGlyphs.js" as RunGlyphs
import "../components" as UI
import "../theme" as T

// The panel's left column: a project dropdown, the section list, and a Delete
// project button. It renders and emits only; Panel.qml owns every piece of
// state (selection, cursor, delete flow) and passes it in.
Item {
  id: sidebar
  objectName: "sidebar"

  property var projects: []
  property var selectedProject: null
  property string section: "board"
  property bool dropdownOpen: false
  property string dropdownQuery: ""
  property int dropdownCursor: 0
  property bool canDelete: false
  property bool documentsEnabled: true
  // How many runs need attention (escalated plus dead), computed by the
  // owner. Rendered as `‼N` by runsAttentionText; card 5.1's Runs row binds
  // `countText: sidebar.runsAttentionText`. No row shows it yet.
  property int runsAttention: 0
  readonly property string runsAttentionText: sidebar.runsAttention > 0
    ? RunGlyphs.glyphOf("escalated") + sidebar.runsAttention : ""
  // The one input for every colour and font: Panel passes its Theme down,
  // and a standalone instance renders with the shell defaults.
  property var theme: T.Theme {}

  signal dropdownToggled()
  signal projectChosen(var project)
  signal queryEdited(string text)
  signal sectionChosen(string section)
  signal deleteRequested()
  signal cursorHovered(int index)
  signal dropdownMove(int delta)
  signal dropdownAccept()
  signal dropdownCancel()
  signal filterKey(var event)

  readonly property bool hasProject: !!selectedProject
  readonly property Item filterItem: filterField
  implicitHeight: Style.space(300)


  ColumnLayout {
    anchors.fill: parent
    spacing: Style.space(8)

    CursorSurface {
      id: projectButton
      objectName: "projectButton"
      Layout.fillWidth: true
      implicitHeight: buttonRow.implicitHeight + Style.spacing.rowPaddingX * 2
      bordered: true
      hasCursor: buttonArea.containsMouse || sidebar.dropdownOpen
      foreground: sidebar.theme.foreground

      RowLayout {
        id: buttonRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)

        UI.ThemedText {
          theme: sidebar.theme
          Layout.fillWidth: true
          text: sidebar.selectedProject ? sidebar.selectedProject.name : "No project"
          color: sidebar.selectedProject ? sidebar.theme.foreground : sidebar.theme.dim
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          text: sidebar.dropdownOpen ? "▴" : "▾"
          color: sidebar.theme.dim
          font.pixelSize: Style.font.body
        }
      }

      MouseArea {
        id: buttonArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: sidebar.dropdownToggled()
      }
    }

    // The glyphs are drawn in the theme's font like every other icon in the
    // shell (see qs.Ui Button's `iconText`), so they must exist in the Nerd
    // Font that font resolves to -- tests/architecture/test_icon_glyphs.py
    // checks every glyph literal in ui/ and vendor/ against the installed
    // fonts. Memories is the Material Design brain (U+F09D1), written as its
    // surrogate pair because it lives outside the BMP.
    NavRow { objectName: "navBoard"; label: "Board"; iconText: "\uf0db"; section: "board"; enabled: sidebar.hasProject }
    NavRow { objectName: "navGraph"; label: "Graph"; iconText: "\uf0e8"; section: "graph"; enabled: sidebar.hasProject }
    NavRow { objectName: "navDocuments"; label: "Documents"; iconText: "\uf15c"; section: "documents"; enabled: sidebar.hasProject && sidebar.documentsEnabled }
    NavRow { objectName: "navMemories"; label: "Memories"; iconText: "\udb82\uddd1"; section: "memories"; enabled: sidebar.hasProject }
    // Appended after Memories, so the digit chords keep their meaning and
    // Issues is Ctrl+5. Its glyph is the Nerd Font bug (U+F188).
    NavRow { objectName: "navIssues"; label: "Issues"; iconText: "\uf188"; section: "issues"; enabled: sidebar.hasProject }

    Item { Layout.fillHeight: true }

    UI.ActionButton {
      objectName: "deleteButton"
      Layout.fillWidth: true
      text: "Delete project…"
      enabled: sidebar.hasProject && sidebar.canDelete
      // The sidebar dims its disabled button a touch less than the rest.
      opacity: enabled ? 1 : 0.4
      tone: "danger"
      theme: sidebar.theme
      onClicked: sidebar.deleteRequested()
    }
  }

  // Overlaid on the sidebar, above the nav rows.
  Rectangle {
    id: dropdown
    objectName: "dropdown"
    visible: sidebar.dropdownOpen
    z: 10
    x: 0
    y: projectButton.y + projectButton.height + Style.space(4)
    width: sidebar.width
    height: dropdownColumn.implicitHeight + Style.space(12)
    color: Color.popups.background
    border.color: Color.popups.border
    border.width: 1
    radius: Style.space(6)

    Column {
      id: dropdownColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.space(6)
      spacing: Style.space(6)

      TextField {
        id: filterField
        objectName: "filterField"
        width: parent.width
        foreground: sidebar.theme.foreground
        placeholderText: "Search projects…"
        text: sidebar.dropdownQuery
        onTextChanged: if (text !== sidebar.dropdownQuery) sidebar.queryEdited(text)

        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Down) { sidebar.dropdownMove(1); event.accepted = true; return }
          if (event.key === Qt.Key_Up) { sidebar.dropdownMove(-1); event.accepted = true; return }
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { sidebar.dropdownAccept(); event.accepted = true; return }
          if (event.key === Qt.Key_Escape) { sidebar.dropdownCancel(); event.accepted = true; return }
          sidebar.filterKey(event)
        }
      }

      UI.ThemedText {
        variant: "small"
        theme: sidebar.theme
        visible: sidebar.projects.length === 0
        width: parent.width
        text: sidebar.dropdownQuery === "" ? "No projects registered." : "No projects match “" + sidebar.dropdownQuery + "”."
        color: sidebar.theme.dim
        wrapMode: Text.WordWrap
      }

      Flickable {
        id: listFlick
        width: parent.width
        height: Math.min(listColumn.implicitHeight, Style.space(240))
        contentHeight: listColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: listColumn
          width: listFlick.width
          spacing: Style.space(2)

          Repeater {
            model: sidebar.projects
            delegate: ProjectItem {}
          }
        }

        function ensureVisible(item) {
          var top = item.y
          var bottom = item.y + item.height
          if (top < contentY) contentY = top
          else if (bottom > contentY + height) contentY = bottom - height
        }
      }
    }
  }

  component NavRow: CursorSurface {
    id: navRow
    property string label: ""
    property string section: ""
    property string iconText: ""
    // An optional count after the label, such as the Runs row's `‼N`; "" (the
    // default) shows nothing, so a row that does not set it is unchanged.
    property string countText: ""

    Layout.fillWidth: true
    implicitHeight: navRowContent.implicitHeight + Style.spacing.rowPaddingX * 2
    current: sidebar.section === section
    hasCursor: navArea.containsMouse && enabled
    opacity: enabled ? 1 : 0.4
    foreground: sidebar.theme.foreground

    Row {
      id: navRowContent
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.leftMargin: Style.space(10)
      spacing: Style.space(8)

      UI.ThemedText {
        // navIconBoard, navIconGraph, ... -- one glyph per section.
        objectName: "navIcon" + navRow.section.charAt(0).toUpperCase() + navRow.section.slice(1)
        theme: sidebar.theme
        anchors.verticalCenter: navLabel.verticalCenter
        width: Style.font.iconSmall
        horizontalAlignment: Text.AlignHCenter
        text: navRow.iconText
        font.pixelSize: Style.font.iconSmall
      }

      UI.ThemedText {
        id: navLabel
        theme: sidebar.theme
        text: navRow.label
        font.bold: navRow.current
      }

      UI.ThemedText {
        // navCountBoard, navCountGraph, ... -- hidden unless the row has a count.
        objectName: "navCount" + navRow.section.charAt(0).toUpperCase() + navRow.section.slice(1)
        theme: sidebar.theme
        anchors.verticalCenter: navLabel.verticalCenter
        visible: navRow.countText !== ""
        text: navRow.countText
        color: sidebar.theme.urgent
        font.bold: true
      }
    }

    MouseArea {
      id: navArea
      anchors.fill: parent
      enabled: navRow.enabled
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: sidebar.sectionChosen(navRow.section)
    }
  }

  component ProjectItem: CursorSurface {
    id: item
    required property var modelData
    required property int index
    objectName: "projectRow" + index

    width: listColumn.width
    implicitHeight: itemLabel.implicitHeight + Style.spacing.rowPaddingX * 2
    hasCursor: sidebar.dropdownCursor === index
    current: !!sidebar.selectedProject && modelData.root_path === sidebar.selectedProject.root_path
    foreground: sidebar.theme.foreground
    onHasCursorChanged: if (hasCursor) listFlick.ensureVisible(item)

    UI.ThemedText {
      id: itemLabel
      theme: sidebar.theme
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      text: item.modelData.name
      elide: Text.ElideRight
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: sidebar.cursorHovered(item.index)
      onClicked: sidebar.projectChosen(item.modelData)
    }
  }
}
