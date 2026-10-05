import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../../core/domain/board.js" as Board
import "../../core/domain/runs.js" as Runs
import "../components/runControlFacts.js" as ControlFacts
import "../components" as UI
import "../theme" as T

// One card, opened from the Board or the Graph: its parent, its blockers and
// its children as keyboard-navigable link rows (an issue blocker is shown with
// its title and open/closed state and opens in the Issues section), plus the kind/status badges,
// the description and the card's brd comments. It reads the board store and opens links through the
// navigator; it owns no state of its own.
Column {
  id: detailCard

  property var app
  property var navigator
  property var theme: T.Theme {}

  // The panel scrolls; a link row that takes the cursor asks for it here.
  signal revealRequested(var item)
  // A run's Cancel was clicked. Cancelling needs a typed confirmation, which is
  // the owner's to ask for; nothing here cancels a run.
  signal cancelRequested(string runId)

  visible: detailCard.app.nav.viewMode === "entry" && !!detailCard.app.board.cardMap[detailCard.app.board.selectedCardId]
  spacing: Style.space(10)

  readonly property var card: detailCard.app.board.cardMap[detailCard.app.board.selectedCardId]

  // The am runs that touch this card (5.3), in am's order: newest first. A
  // card's runs are its history, so a merged or canceled card still lists them;
  // nothing is listed while am is not installed.
  readonly property var touchingRuns: !detailCard.card || detailCard.app.runs.amStatus === "missing"
    ? [] : Runs.runsTouching(detailCard.app.runs.runs, detailCard.card.id)
  // Ages are read against the clock once per run snapshot: there is no timer.
  readonly property real nowMs: detailCard.touchingRuns ? Date.now() : 0
  // A run row's control button: pause and resume go straight to the store, a
  // cancel only asks (cancelRequested).
  function requestControl(action, run) {
    var id = ControlFacts.runIdOf(run)
    if (id === "") return
    if (action === "cancel") detailCard.cancelRequested(id)
    else detailCard.app.runs.control(action, id)
  }

  DetailLink {
    visible: !!(detailCard.card && detailCard.card.parentId)
    width: parent.width
    prefix: "↑ "
    resolved: detailCard.card && detailCard.card.parentId
      ? detailCard.app.board.resolvedCard(detailCard.card.parentId) : ({ title: "", status: "", inBoard: false })
    rowIndex: detailCard.card && detailCard.card.parentId ? detailCard.app.board.linkIndex("parent", detailCard.card.parentId) : -1
    onActivated: if (resolved.inBoard) detailCard.navigator.openCard(detailCard.card.parentId)
  }

  UI.ThemedText {
    variant: "heading"
    theme: detailCard.theme
    width: parent.width
    text: detailCard.card ? detailCard.card.title : ""
    font.bold: true
    wrapMode: Text.WordWrap
  }

  Row {
    spacing: Style.space(6)

    Badge {
      text: detailCard.card ? Board.kindLabel(detailCard.card.depth) : ""
      tone: detailCard.theme.foreground
    }

    Badge {
      text: detailCard.card ? detailCard.app.board.statusText(detailCard.card.status) : ""
      tone: detailCard.card ? Board.statusColor(detailCard.card.status, detailCard.theme.dim) : detailCard.theme.dim
    }

    // Only on a card brd reports blocked, and only while an open issue blocks it.
    Badge {
      objectName: "cardDetailIssueBadge"
      visible: text !== ""
      text: detailCard.card ? Board.openIssueLabel(detailCard.card, detailCard.app.board.issueMap) : ""
      tone: Board.statusColor("blocked", detailCard.theme.dim)
    }
  }

  PanelSeparator { foreground: detailCard.theme.foreground }

  UI.ThemedText {
    variant: "small"
    theme: detailCard.theme
    width: parent.width
    text: (detailCard.card && detailCard.card.description) ? detailCard.card.description : "No description."
    wrapMode: Text.WordWrap
    textFormat: Text.MarkdownText
  }

  PanelSectionHeader {
    visible: !!(detailCard.card && detailCard.card.blocked_by && detailCard.card.blocked_by.length > 0)
    text: "BLOCKED BY"
    foreground: detailCard.theme.foreground
    fontFamily: detailCard.theme.fontFamily
  }

  Repeater {
    model: (detailCard.card && detailCard.card.blocked_by) ? detailCard.card.blocked_by : []

    DetailLink {
      required property string modelData
      width: parent.width
      resolved: detailCard.app.board.resolvedCard(modelData)
      rowIndex: detailCard.app.board.linkIndex("blocker", modelData)
      // A card opens as a card, an issue the board knows opens as an issue.
      onActivated: detailCard.navigator.openBlocker(modelData)
    }
  }

  PanelSectionHeader {
    visible: !!(detailCard.card && detailCard.card.children && detailCard.card.children.length > 0)
    text: "CHILDREN"
    foreground: detailCard.theme.foreground
    fontFamily: detailCard.theme.fontFamily
  }

  Repeater {
    model: (detailCard.card && detailCard.card.children) ? detailCard.card.children : []

    DetailLink {
      required property var modelData
      width: parent.width
      resolved: detailCard.app.board.resolvedCard(modelData.id)
      rowIndex: detailCard.app.board.linkIndex("child", modelData.id)
      onActivated: detailCard.navigator.openCard(modelData.id)
    }
  }

  PanelSectionHeader {
    objectName: "cardRunsHeader"
    visible: detailCard.touchingRuns.length > 0
    text: "RUNS"
    foreground: detailCard.theme.foreground
    fontFamily: detailCard.theme.fontFamily
  }

  Repeater {
    model: detailCard.touchingRuns.length

    CardRunRow {
      width: parent.width
    }
  }

  // The card's comments, from the export the extras store holds. Read-only,
  // like everything else on this screen.
  UI.CommentList {
    objectName: "cardComments"
    width: parent.width
    theme: detailCard.theme
    comments: detailCard.card ? detailCard.app.extras.commentsFor(detailCard.card.id) : []
  }

  // The card detail's own pill: bordered, translucent and wider than the shared
  // ui/components/Badge, which is a filled chip. A documented duplication: the
  // two designs are not the same component.
  component Badge: Rectangle {
    id: badge
    property string text: ""
    property color tone: detailCard.theme.foreground

    visible: text !== ""
    width: implicitWidth
    height: implicitHeight
    implicitWidth: badgeLabel.implicitWidth + Style.space(14)
    implicitHeight: badgeLabel.implicitHeight + Style.space(4)
    radius: height / 2
    color: Qt.rgba(tone.r, tone.g, tone.b, 0.16)
    border.color: tone
    border.width: 1

    UI.ThemedText {
      id: badgeLabel
      variant: "caption"
      theme: detailCard.theme
      anchors.centerIn: parent
      text: badge.text
      color: badge.tone
      font.bold: true
    }
  }

  // One run that touches the card: its state glyph, short id, title, current
  // phase and age, and its RunControls under them. Mouse-activated only
  // (`index` stays -1): the keyboard's link list is the card's brd links. A
  // click opens Run detail, whose Back comes back here; a run that vanished
  // meanwhile opens nothing. A click on a control button never opens the run.
  component CardRunRow: UI.ListRow {
    id: runRow
    // The model is a count, so this is the run's position in touchingRuns. The
    // run is read back by position because a Repeater's converted modelData copy
    // would lose the nested arrays the domain helpers read.
    required property int modelData
    readonly property var run: detailCard.touchingRuns[runRow.modelData] || null

    objectName: "cardRunRow" + runRow.modelData
    theme: detailCard.theme
    opacity: detailCard.app.runs.stale ? 0.5 : 1
    contentMargin: Style.space(6)
    onActivated: detailCard.navigator.openRun(runRow.run ? runRow.run.id : "", "entry")

    Row {
      width: parent.width
      spacing: Style.space(8)

      UI.RunBadge {
        theme: detailCard.theme
        state: Runs.runState(runRow.run)
        active: !detailCard.app.runs.stale
      }

      UI.ThemedText {
        objectName: "cardRunId" + runRow.modelData
        variant: "caption"
        theme: detailCard.theme
        text: Runs.shortId(runRow.run)
      }

      UI.ThemedText {
        objectName: "cardRunTitle" + runRow.modelData
        variant: "small"
        theme: detailCard.theme
        text: Runs.runTitle(runRow.run)
      }

      UI.ThemedText {
        objectName: "cardRunPhase" + runRow.modelData
        variant: "caption"
        theme: detailCard.theme
        visible: text !== ""
        text: Runs.currentPhase(runRow.run)
      }

      UI.ThemedText {
        objectName: "cardRunAge" + runRow.modelData
        variant: "caption"
        theme: detailCard.theme
        visible: text !== ""
        text: Runs.runAgeText(runRow.run, detailCard.nowMs)
      }
    }

    // A story or subtask card shares its run with its siblings: the labels say
    // so ("Pause run") and the caption spells it out. A finished run shows
    // nothing, so a merged card's history reads as before.
    actions: [
      UI.RunControls {
        objectName: "cardRunControls" + runRow.modelData
        width: parent.width
        theme: detailCard.theme
        run: runRow.run
        pendingAction: ControlFacts.pendingOf(detailCard.app.runs.pending, runRow.run)
        waiting: ControlFacts.waitingOf(detailCard.app.runs.stillWaiting, runRow.run)
        waitingText: detailCard.app.runs.stillWaitingText
        errorText: ControlFacts.errorOf(detailCard.app.runs.lastControlError, detailCard.app.runs.lastControlErrorRunId, runRow.run)
        wholeRun: !!detailCard.card && detailCard.card.depth >= 1
        showButtons: true
        onActionRequested: function(action) { detailCard.requestControl(action, runRow.run) }
      }
    ]
  }

  component DetailLink: UI.ListRow {
    id: detailLink
    property var resolved: ({ title: "", status: "", inBoard: true })
    property alias rowIndex: detailLink.index
    property string prefix: ""
    readonly property bool isIssue: detailLink.resolved.kind === "issue"

    theme: detailCard.theme
    // A closed issue stays in blocked_by but no longer blocks.
    opacity: detailLink.isIssue && detailLink.resolved.status === "closed" ? 0.5 : 1
    cursorIndex: detailCard.app.nav.cursorIndex
    scrollOnCursor: detailCard.app.nav.scrollOnCursor
    contentMargin: Style.space(6)
    hoverCursorShape: detailLink.resolved.inBoard || detailLink.isIssue ? Qt.PointingHandCursor : Qt.ArrowCursor
    onHovered: function(index) { detailCard.navigator.hoverCursor(index) }
    onRevealRequested: function(item) { detailCard.revealRequested(item) }

    RowLayout {
      id: detailLinkLayout
      width: parent.width

      UI.ThemedText {
        variant: "small"
        theme: detailCard.theme
        Layout.fillWidth: true
        text: detailLink.prefix + detailLink.resolved.title
          + (detailLink.resolved.inBoard || detailLink.isIssue ? "" : " (not in this board)")
        color: detailLink.resolved.inBoard || detailLink.isIssue ? detailCard.theme.foreground : detailCard.theme.dim
        elide: Text.ElideRight
      }

      UI.ThemedText {
        variant: "caption"
        theme: detailCard.theme
        visible: detailLink.resolved.inBoard || detailLink.isIssue
        text: detailLink.isIssue ? Board.issueBlockerLabel(detailLink.resolved.status)
                                 : "[" + detailLink.resolved.status + "]"
        color: detailLink.isIssue
          ? (detailLink.resolved.status === "open" ? Board.statusColor("blocked", detailCard.theme.dim) : detailCard.theme.dim)
          : Board.statusColor(detailLink.resolved.status, detailCard.theme.dim)
      }
    }
  }
}
