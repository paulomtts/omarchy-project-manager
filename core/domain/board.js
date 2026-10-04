.pragma library
.import "text.js" as Text

// Card shape, as returned by `brd tree`:
// {id, title, description, status, blocked_by, created_at, updated_at, children}
// indexTree() additionally injects `parentId` and `depth` onto every card it visits.

// Walks the forest depth-first, pre-order. Mutates every card in place to
// add parentId (null for a root) and depth (0 for a root), and returns a flat
// id -> card lookup covering every card in the forest.
function indexTree(roots) {
  var cardMap = {}

  function visit(card, parentId, depth) {
    card.parentId = parentId
    card.depth = depth
    cardMap[card.id] = card
    ;(card.children || []).forEach(function(child) {
      visit(child, card.id, depth + 1)
    })
  }

  ;(roots || []).forEach(function(root) { visit(root, null, 0) })
  return { cardMap: cardMap }
}

// Descendant-only progress: card's own status never counts, so a "done"
// parent with still-open children doesn't read as complete. "merged" counts as
// done; "canceled" work is out of scope, so it is left out of the total.
function subtreeCounts(card) {
  var done = 0
  var total = 0

  function visit(node) {
    ;(node.children || []).forEach(function(child) {
      if (child.status !== "canceled") {
        total += 1
        if (child.status === "done" || child.status === "merged") done += 1
      }
      visit(child)
    })
  }

  visit(card)
  return { done: done, total: total }
}

// True if `card` itself matches, or any descendant does -- so an ancestor
// of a match stays visible even though it doesn't match on its own title.
function subtreeMatches(card, query) {
  if (!card) return false
  if (Text.matchesQuery(card.title, query)) return true
  return (card.children || []).some(function(child) { return subtreeMatches(child, query) })
}

// The shell theme has no green/orange/purple/red tokens, so these hues are fixed; todo
// (and anything unrecognised) takes the caller's neutral colour so it still
// follows the theme.
function statusColor(status, fallback) {
  if (status === "done") return "#7fb069"
  if (status === "blocked") return "#e8954a"
  if (status === "in_progress") return "#5fa8d3"
  if (status === "merged") return "#9b72cf"
  if (status === "canceled") return "#d9534f"
  return fallback
}

// brd has closed this card's work: merged or canceled (or archived, should brd
// ever report it). The one list the screens gate am run marks on (a visibility
// rule only, never a run state) and Run detail dims its rows by.
function isClosedStatus(status) {
  return status === "merged" || status === "canceled" || status === "archived"
}

// Depth in the brd hierarchy: milestone > story > subtask.
function kindLabel(depth) {
  if (typeof depth !== "number" || depth < 0) return "Card"
  if (depth === 0) return "Milestone"
  if (depth === 1) return "Story"
  return "Subtask"
}

// brd derives "blocked" on top of a stored "todo"; the Board has no blocked
// section, so such a card lives in Todo.
function effectiveStatus(card) {
  if (!card || card.status === "blocked") return "todo"
  return card.status
}

// Top-level cards in the order the Board shows them: section by section.
function boardOrder(roots, statuses) {
  var out = []
  statuses.forEach(function(status) {
    ;(roots || []).forEach(function(card) {
      if (effectiveStatus(card) === status) out.push(card)
    })
  })
  return out
}

// Issue shape, as returned by `brd issue list`:
// {id, kind: "issue", title, body, status: "open"|"closed", close_reason, blocks, ...}
// A card's blocked_by may name an issue; closing it unblocks the card but the
// id stays in blocked_by. Returns id -> {id, title, status}, all a blocker
// row or the graph needs.
function indexIssues(issues) {
  var issueMap = {}
  ;(issues || []).forEach(function(issue) {
    if (!issue || !issue.id) return
    issueMap[issue.id] = { id: issue.id, title: issue.title || issue.id,
                           status: issue.status === "closed" ? "closed" : "open" }
  })
  return issueMap
}

// How many OPEN issues (from indexIssues) block this card directly. Closed
// issues stay in blocked_by but no longer block, so they add nothing, and a
// repeated id counts once.
function openIssueCount(card, issueMap) {
  if (!card || !issueMap) return 0
  var seen = {}
  var count = 0
  ;(card.blocked_by || []).forEach(function(id) {
    if (seen[id]) return
    seen[id] = true
    if (issueMap[id] && issueMap[id].status === "open") count += 1
  })
  return count
}

// The badge a card blocked by an open issue carries. Only a card brd itself
// reports as blocked is flagged -- one whose blockers are all resolved is not.
function openIssueLabel(card, issueMap) {
  if (!card || card.status !== "blocked") return ""
  var count = openIssueCount(card, issueMap)
  return count === 0 ? "" : count + (count === 1 ? " open issue" : " open issues")
}

// What a link row shows for an id: a card in this board, else an issue, else
// the bare id. Only a card is inBoard (navigable).
function resolvedCard(id, cardMap, issueMap) {
  var card = (cardMap || {})[id]
  if (card) return { id: id, title: card.title, status: card.status, inBoard: true }
  var issue = (issueMap || {})[id]
  if (issue) return { id: id, title: issue.title, status: issue.status, kind: "issue", inBoard: false }
  return { id: id, title: id, status: "", inBoard: false }
}

function issueBlockerLabel(status) {
  return "Issue · " + status
}

// The clickable rows of a card's detail view, in display order. A blocker is
// navigable when it is a card of this board (it opens as a card) or an issue
// the issue map knows (it opens in the Issues section); an id that is neither
// cannot be opened, so it is not listed.
function detailLinks(card, cardMap, issueMap) {
  if (!card) return []
  var issues = issueMap || {}
  var links = []
  if (card.parentId && cardMap[card.parentId]) links.push({ section: "parent", id: card.parentId })
  ;(card.blocked_by || []).forEach(function(id) {
    if (cardMap[id] || issues[id]) links.push({ section: "blocker", id: id })
  })
  ;(card.children || []).forEach(function(child) {
    links.push({ section: "child", id: child.id })
  })
  return links
}

// A card's ancestors, outermost first, as ids: the trail the breadcrumbs walk.
// Cards carry the `parentId` indexTree() injected; a broken chain simply stops.
function ancestorIds(id, cardMap) {
  var out = []
  var card = cardMap[id]
  while (card && card.parentId && cardMap[card.parentId] && out.indexOf(card.parentId) < 0) {
    out.unshift(card.parentId)
    card = cardMap[card.parentId]
  }
  return out
}
