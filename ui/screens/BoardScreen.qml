import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../../core/domain/board.js" as Board
import "../../core/domain/runs.js" as Runs
import "../components" as UI
import "../theme" as T

// The Board section: one column per status, each holding the top-level cards
// that belong to it. It reads the board store and asks the navigator to open a
// card or move the cursor; it owns no state of its own.
Column {
  id: screen

  property var app
  property var navigator
  property var theme: T.Theme {}

  // The panel scrolls; a card that takes the cursor asks for it here.
  signal revealRequested(var item)

  visible: screen.app.nav.viewMode === "board" && !!screen.app.projects.selectedProject
  spacing: Style.space(10)

  // ---- am run marks (5.3): read from the run store through `app`, never from
  // brd status. A merged or canceled card (or archived, should brd ever report
  // it) draws none -- a visibility rule only -- and no card draws any while am
  // is not installed.
  readonly property bool amMissing: screen.app.runs.amStatus === "missing"

  function hidesRunMarks(card) {
    return screen.amMissing || !card || Board.isClosedStatus(card.status)
  }

  UI.ThemedText {
    variant: "dim"
    theme: screen.theme
    visible: screen.app.board.cardRoots.length === 0 && screen.app.projects.loadError === ""
    width: parent.width
    text: "This project's board is empty."
    wrapMode: Text.WordWrap
  }

  UI.ThemedText {
    variant: "dim"
    theme: screen.theme
    visible: screen.app.board.cardRoots.length > 0 && screen.app.board.visibleBoardRoots.length === 0
    width: parent.width
    text: "No cards match “" + screen.app.nav.searchQuery + "”."
    wrapMode: Text.WordWrap
  }

  Repeater {
    model: screen.app.board.statuses

    Column {
      required property string modelData
      width: parent.width
      spacing: Style.space(6)

      PanelSectionHeader {
        text: screen.app.board.statusLabel(modelData) + " (" + screen.app.board.boardColumn(modelData).length + ")"
        foreground: Board.statusColor(modelData, screen.theme.foreground)
        fontFamily: screen.theme.fontFamily
      }

      Repeater {
        model: screen.app.board.boardColumn(modelData)

        BoardCard {
          required property var modelData
          width: parent.width
          cardIndex: screen.app.board.boardIndexOf(modelData.id)
          title: modelData.title
          status: modelData.status
          issueLabel: Board.openIssueLabel(modelData, screen.app.board.issueMap)
          progress: Board.subtreeCounts(modelData)
          runState: screen.hidesRunMarks(modelData) ? null : Runs.cardRunState(screen.app.runs.runs, modelData.id)
          runRollup: screen.hidesRunMarks(modelData) ? null : Runs.rollup(screen.app.runs.runs, { id: modelData.id })
          onActivated: screen.navigator.openCard(modelData.id)
        }
      }
    }
  }

  component BoardCard: CursorSurface {
    id: boardCard
    property int cardIndex: -1
    property string title: ""
    property string status: "todo"
    property string issueLabel: ""
    property var progress: ({ done: 0, total: 0 })
    // Runs.cardRunState / Runs.rollup for this card, or null for no mark.
    property var runState: null
    property var runRollup: null
    // Glyph + phase rather than counts: a card its winning run lists as a
    // subtask. The Board shows roots only (depth 0), so depth never decides it.
    readonly property bool subtaskRun: !!boardCard.runState
      && typeof boardCard.runState.phase === "string" && boardCard.runState.phase !== ""
    signal activated()

    hasCursor: cardIndex >= 0 && screen.app.nav.cursorIndex === cardIndex
    onHasCursorChanged: if (hasCursor && screen.app.nav.scrollOnCursor) screen.revealRequested(boardCard)
    foreground: screen.theme.foreground
    bordered: true
    implicitHeight: cardLayout.implicitHeight + Style.space(16)

    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.margins: Style.space(4)
      width: Style.space(3)
      radius: width / 2
      color: Board.statusColor(boardCard.status, screen.theme.dim)
    }

    ColumnLayout {
      id: cardLayout
      anchors.fill: parent
      anchors.margins: Style.space(8)
      anchors.leftMargin: Style.space(14)
      spacing: Style.space(4)

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(6)

        UI.ThemedText {
          theme: screen.theme
          Layout.fillWidth: true
          text: boardCard.title
          wrapMode: Text.WordWrap
        }

        UI.RunMark {
          id: boardRunMark
          Layout.alignment: Qt.AlignTop | Qt.AlignRight
          theme: screen.theme
          runState: boardCard.runState
          rollup: boardCard.runRollup
          subtask: boardCard.subtaskRun
          stale: screen.app.runs.stale
        }
      }

      // A milestone's or story's am run rollup, under its title; hides itself
      // without one, and a subtask has none.
      UI.RunRollupBar {
        Layout.fillWidth: true
        theme: screen.theme
        rollup: boardCard.subtaskRun ? null : boardCard.runRollup
        opacity: boardRunMark.dimmed ? 0.5 : 1
      }

      Row {
        Layout.fillWidth: true
        spacing: Style.space(6)
        visible: boardCard.status === "blocked"

        UI.ThemedText {
          variant: "caption"
          theme: screen.theme
          text: "Blocked"
          color: Board.statusColor("blocked", screen.theme.dim)
          font.bold: true
        }

        UI.ThemedText {
          objectName: "boardCardIssues" + boardCard.cardIndex
          variant: "caption"
          theme: screen.theme
          visible: text !== ""
          text: boardCard.issueLabel
          color: Board.statusColor("blocked", screen.theme.dim)
        }
      }

      UI.ThemedText {
        variant: "caption"
        theme: screen.theme
        visible: boardCard.progress.total > 0
        text: boardCard.progress.done + "/" + boardCard.progress.total + " done"
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: if (boardCard.cardIndex >= 0) screen.navigator.hoverCursor(boardCard.cardIndex)
      onClicked: boardCard.activated()
    }
  }
}
