.pragma library
.import "board.js" as Board
.import "../../vendor/canvas/layout.js" as Layout

var GRAPH_NODE_W = 230
var GRAPH_NODE_H = 78

// Kept as graph.js's own name for the graph model; the counting itself lives
// in board.js, which the card badge uses too -- one implementation, one test.
function openIssueCount(card, issueMap) {
  return Board.openIssueCount(card, issueMap)
}

function openIssueLabel(count) {
  if (!count) return ""
  return count + (count === 1 ? " open issue" : " open issues")
}

// One node per milestone (top-level card), one edge per blocked_by link between
// two milestones (blocker -> blocked; links to sub-cards, issues or unknown ids
// are not milestone dependencies and are skipped). Each node also carries how
// many open issues block it -- only when brd reports it blocked, since the
// count is there to explain that status. Positions come from the canvas's own layered
// layout so the panel can navigate by geometry.
// The blocker -> blocked arrows of a card list: only blockers `known` holds (an
// id nothing in the view carries -- an issue, a card of another level, a ghost
// -- is no dependency of it), never a self-link, and the same pair only ONCE
// however often brd repeats it in blocked_by. `known` is keyed through mapKey,
// so an id like "constructor" cannot match an Object.prototype member.

// Every map in this file that is keyed by a CARD ID goes through this. A card
// is named by brd, so a card can be called "constructor" -- which matches a
// member every object has -- or "__proto__", which cannot even be written as a
// plain key. The canvas's own positions.js keys its maps exactly this way.
function mapKey(id) { return "id:" + id }

// The value a map holds, or undefined: neither walks the prototype chain, so
// the position maps below -- which cross into QML keyed by card id, not by
// mapKey -- are read just as safely.
function has(map, key) { return !!map && Object.prototype.hasOwnProperty.call(map, key) }
function get(map, key) { return has(map, key) ? map[key] : undefined }

function dependencyEdges(cards, known) {
  var edges = []
  var seen = {}
  ;(cards || []).forEach(function(card) {
    ;(card.blocked_by || []).forEach(function(blocker) {
      if (!has(known, mapKey(blocker)) || blocker === card.id) return
      var id = blocker + ">" + card.id
      if (has(seen, mapKey(id))) return
      seen[mapKey(id)] = true
      edges.push({ id: id, from: blocker, to: card.id })
    })
  })
  return edges
}

// The cards without any archived one, at every depth: an archived card goes with
// its whole subtree, and nothing else changes. The input is not touched (cards
// are copied only where a child was dropped), so the board's own tree keeps its
// archived cards for the toggle to bring back.
function withoutArchived(cards) {
  return (cards || []).filter(function(card) { return card.status !== "archived" }).map(function(card) {
    var children = card.children || []
    var kept = withoutArchived(children)
    if (kept.length === children.length) return card
    var copy = {}
    Object.keys(card).forEach(function(key) { copy[key] = card[key] })
    copy.children = kept
    return copy
  })
}

function graphModel(roots, issueMap) {
  var cards = roots || []
  var known = {}
  cards.forEach(function(card) { known[mapKey(card.id)] = true })

  var nodes = cards.map(function(card) {
    var counts = Board.subtreeCounts(card)
    return { id: card.id, title: card.title, status: card.status,
             done: counts.done, total: counts.total,
             openIssues: card.status === "blocked" ? openIssueCount(card, issueMap) : 0,
             w: GRAPH_NODE_W, h: GRAPH_NODE_H }
  })
  var edges = dependencyEdges(cards, known)

  var placed = nodes.length > 0 ? Layout.layout(nodes, edges) : {}
  nodes.forEach(function(node) {
    var at = get(placed, node.id)
    node.x = at ? at.x : 0
    node.y = at ? at.y : 0
  })
  return { nodes: nodes, edges: edges }
}

// ---- Story view -----------------------------------------------------------
// One node per STORY (a milestone's direct child), every milestone's stories at
// once, each milestone's stories boxed together. Same node size as a milestone
// node; the done/total text is dropped in favour of one pip per subtask.
var STORY_NODE_W = 230
var STORY_NODE_H = 78
// How many pips a node shows before the rest collapse into a "+N". Six fit
// across the node beside the "+N" at the sizes above.
var STORY_PIP_CAP = 6
// The padding a group box keeps around its stories, and the strip at the top
// that carries the milestone title.
var GROUP_PAD = 16
var GROUP_HEADER = 30

// The status a subtask's pip is coloured by: the card's own, except that a card
// an OPEN issue blocks reads as blocked (brd already derives that status, and
// this holds even when a board was read before its issues were).
function pipStatus(card, issueMap) {
  if (!card) return "todo"
  if (card.status === "blocked" || openIssueCount(card, issueMap) > 0) return "blocked"
  return card.status
}

// A story's pips: one per direct child, capped. Over the cap, one slot is given
// to the "+N" so the node never grows -- morePips then counts everything the
// visible pips leave out.
function storyPips(story, issueMap) {
  var children = (story && story.children) || []
  var shown = children.length > STORY_PIP_CAP ? STORY_PIP_CAP - 1 : children.length
  var pips = []
  for (var i = 0; i < shown; i++)
    pips.push({ id: children[i].id, status: pipStatus(children[i], issueMap) })
  return { pips: pips, morePips: children.length - shown }
}

function isNumber(value) {
  return typeof value === "number" && isFinite(value)
}

// Where a story actually is: the position `at` holds for it (a dragged story,
// a moved box), else the one the layout gave it.
function positionOf(node, at) {
  return has(at, node.id) ? at[node.id] : node
}

// A position map plus one entry, as a NEW map: QML only notices a var property
// whose object changed, never one written in place. A junk position is no
// position and is dropped rather than stored.
function withPosition(at, id, x, y) {
  var next = copyPositions(at)
  if (isNumber(x) && isNumber(y)) next[id] = { x: x, y: y }
  return next
}

// A position map has no prototype: it is keyed by raw card id (it crosses into
// QML, where a story is looked up by the id it has), so a story called
// "__proto__" would otherwise not be storable at all.
function copyPositions(at) {
  var next = Object.create(null)
  for (var key in at) {
    if (has(at, key)) next[key] = at[key]
  }
  return next
}

// The nodes as they should be drawn: copies carrying the position `at` holds
// for them. The caller's own nodes are never written (the canvas owns its
// model, this only hands it one).
function placedNodes(nodes, at) {
  return (nodes || []).map(function(node) {
    var position = positionOf(node, at)
    var copy = {}
    for (var key in node) {
      if (has(node, key)) copy[key] = node[key]
    }
    copy.x = position.x
    copy.y = position.y
    return copy
  })
}

// The live box of every group: its own stories' bounding box, padded, with the
// strip at the top that carries the label. Membership is the story's
// `milestoneId` and nothing else, so a story dragged over another milestone's
// box is never adopted by it -- its own box follows it instead. A group with no
// placed story draws no box.
function storyGroupRects(groups, nodes, at) {
  var bounds = {}
  ;(nodes || []).forEach(function(node) {
    var position = positionOf(node, at)
    if (!isNumber(position.x) || !isNumber(position.y)) return
    var w = isNumber(node.w) ? node.w : 0
    var h = isNumber(node.h) ? node.h : 0
    var box = get(bounds, mapKey(node.milestoneId))
    if (!box) {
      bounds[mapKey(node.milestoneId)] = { minX: position.x, minY: position.y,
                                           maxX: position.x + w, maxY: position.y + h }
      return
    }
    box.minX = Math.min(box.minX, position.x)
    box.minY = Math.min(box.minY, position.y)
    box.maxX = Math.max(box.maxX, position.x + w)
    box.maxY = Math.max(box.maxY, position.y + h)
  })

  var rects = []
  ;(groups || []).forEach(function(group) {
    var box = get(bounds, mapKey(group.id))
    if (!box) return
    rects.push({ id: group.id, title: group.title,
                 x: box.minX - GROUP_PAD, y: box.minY - GROUP_HEADER,
                 w: (box.maxX - box.minX) + 2 * GROUP_PAD,
                 h: (box.maxY - box.minY) + GROUP_HEADER + GROUP_PAD })
  })
  return rects
}

// Moving a whole box: every story of that milestone shifts by the same world
// delta, from where it is NOW, and nothing else moves. Returns a new position
// map (see withPosition); a junk delta moves nothing.
function moveGroupPositions(nodes, groupId, dx, dy, at) {
  var next = copyPositions(at)
  if (!isNumber(dx) || !isNumber(dy)) return next
  ;(nodes || []).forEach(function(node) {
    if (node.milestoneId !== groupId) return
    var position = positionOf(node, at)
    if (!isNumber(position.x) || !isNumber(position.y)) return
    next[node.id] = { x: position.x + dx, y: position.y + dy }
  })
  return next
}

// Adopting where one box's stories have ENDED UP: the arrangement gains that
// box's members at the positions `live` reports for them, and nothing else
// changes. This is what a finished box drag keeps -- the drag itself moves the
// stories through the canvas's working positions, frame by frame, without
// laying the graph out again.
function adoptGroupPositions(nodes, groupId, at, live) {
  var next = copyPositions(at)
  ;(nodes || []).forEach(function(node) {
    if (node.milestoneId !== groupId) return
    var position = get(live, node.id)
    if (!position || !isNumber(position.x) || !isNumber(position.y)) return
    next[node.id] = { x: position.x, y: position.y }
  })
  return next
}

// The story graph: {nodes, edges, groups, groupEdges}. `nodes` are the stories of every
// milestone in board order, `edges` their story-to-story blocked_by links
// (a blocker in another milestone simply draws across two boxes), and `groups`
// one labelled box per milestone that HAS stories, enclosing exactly its own.
// Positions come from the canvas layout twice: once inside each box, once over
// the boxes themselves, so no two boxes overlap.
function storyGraphModel(roots, issueMap) {
  var milestones = roots || []
  var nodes = []
  var cards = []
  var groups = []
  var groupOf = {}

  milestones.forEach(function(milestone) {
    var stories = milestone.children || []
    if (stories.length === 0) return
    var group = { id: milestone.id, title: milestone.title, stories: [], x: 0, y: 0, w: 0, h: 0 }
    stories.forEach(function(story) {
      var pips = storyPips(story, issueMap)
      var node = { id: story.id, title: story.title, status: story.status,
                   milestoneId: milestone.id,
                   openIssues: story.status === "blocked" ? openIssueCount(story, issueMap) : 0,
                   pips: pips.pips, morePips: pips.morePips,
                   w: STORY_NODE_W, h: STORY_NODE_H }
      groupOf[mapKey(story.id)] = milestone.id
      group.stories.push(node)
      nodes.push(node)
      cards.push(story)
    })
    groups.push(group)
  })

  // Story links only: a blocker that is a milestone, a subtask, an issue or an
  // unknown id is not a story dependency.
  var edges = dependencyEdges(cards, groupOf)

  // Inside every box: the stories of that milestone, laid out by the links that
  // stay inside it. The box is the bounding box of the result, padded, with a
  // strip at the top for the label.
  var offsets = {}
  groups.forEach(function(group) {
    var inner = edges.filter(function(edge) {
      return get(groupOf, mapKey(edge.from)) === group.id && get(groupOf, mapKey(edge.to)) === group.id
    })
    var placed = Layout.layout(group.stories, inner,
                               { rankGap: 60, nodeGap: 24,
                                 defaultWidth: STORY_NODE_W, defaultHeight: STORY_NODE_H })
    var minX = 0, minY = 0, maxX = 0, maxY = 0
    group.stories.forEach(function(node, index) {
      var at = get(placed, node.id) || { x: 0, y: 0 }
      if (index === 0) { minX = at.x; minY = at.y; maxX = at.x + node.w; maxY = at.y + node.h }
      minX = Math.min(minX, at.x); minY = Math.min(minY, at.y)
      maxX = Math.max(maxX, at.x + node.w); maxY = Math.max(maxY, at.y + node.h)
      offsets[mapKey(node.id)] = at
    })
    group.stories.forEach(function(node) {
      offsets[mapKey(node.id)] = { x: get(offsets, mapKey(node.id)).x - minX + GROUP_PAD,
                                   y: get(offsets, mapKey(node.id)).y - minY + GROUP_HEADER }
    })
    group.w = (maxX - minX) + 2 * GROUP_PAD
    group.h = (maxY - minY) + GROUP_HEADER + GROUP_PAD
  })

  // Between the boxes, and ONE derivation for both what ranks them and what is
  // drawn between them: box A -> B when brd says milestone B is blocked by
  // milestone A (the milestone view's own edges, restricted to the milestones
  // that have a box), and when any story of B is blocked by a story of A.
  // Deduplicated, never a box to itself, never to a milestone without a box.
  var boxed = {}
  var boxedCards = []
  groups.forEach(function(group) { boxed[mapKey(group.id)] = true })
  milestones.forEach(function(milestone) {
    if (has(boxed, mapKey(milestone.id))) boxedCards.push(milestone)
  })
  var groupEdges = dependencyEdges(boxedCards, boxed)
  var seenGroupEdge = {}
  groupEdges.forEach(function(edge) { seenGroupEdge[mapKey(edge.id)] = true })
  edges.forEach(function(edge) {
    var from = get(groupOf, mapKey(edge.from))
    var to = get(groupOf, mapKey(edge.to))
    if (from === to) return
    var key = from + ">" + to
    if (has(seenGroupEdge, mapKey(key))) return
    seenGroupEdge[mapKey(key)] = true
    groupEdges.push({ id: key, from: from, to: to })
  })

  var placedGroups = groups.length > 0
    ? Layout.layout(groups.map(function(group) { return { id: group.id, w: group.w, h: group.h } }),
                    groupEdges, { rankGap: 100, nodeGap: 60 })
    : {}
  groups.forEach(function(group) {
    var at = get(placedGroups, group.id) || { x: 0, y: 0 }
    group.x = at.x
    group.y = at.y
    group.stories.forEach(function(node) {
      node.x = group.x + get(offsets, mapKey(node.id)).x
      node.y = group.y + get(offsets, mapKey(node.id)).y
    })
  })

  // The boxes themselves come from the stories' final positions, through the
  // very function the view re-runs live while a story is dragged: the model's
  // boxes and the drawn ones are one derivation, so they cannot drift apart.
  return { nodes: nodes, edges: edges, groupEdges: groupEdges,
           groups: storyGroupRects(groups, nodes, {}) }
}

// Keyboard selection on the graph: the nearest node whose centre lies in the
// given direction ("left"|"right"|"up"|"down"), preferring nodes in line with
// the current one. Nothing selected (or an unknown id) picks the first node.
function graphMove(nodes, currentId, direction) {
  var list = nodes || []
  if (list.length === 0) return ""
  var current = null
  list.forEach(function(n) { if (n.id === currentId) current = n })
  if (!current) return list[0].id

  function cx(n) { return n.x + (n.w || 0) / 2 }
  function cy(n) { return n.y + (n.h || 0) / 2 }
  var best = null
  var bestScore = Infinity
  list.forEach(function(n) {
    if (n === current) return
    var dx = cx(n) - cx(current)
    var dy = cy(n) - cy(current)
    var along = direction === "right" ? dx : direction === "left" ? -dx : direction === "down" ? dy : -dy
    var across = (direction === "left" || direction === "right") ? dy : dx
    if (along <= 0) return
    var score = along + 2 * Math.abs(across)
    if (score < bestScore) { bestScore = score; best = n }
  })
  return best ? best.id : current.id
}
