.pragma library
.import "results.js" as Results
.import "taxonomy.js" as Taxonomy
.import "text.js" as Text
.import "documents.js" as Documents

// The three read-only brd views' data, parsed from `brd export` (comments,
// refs, issues) and `brd doc list` (registered documents). Pure: no Qt, no I/O.
// The export's `documents[]` carry every registered file's full content; they
// are dropped here and never indexed -- the Documents screen asks
// `brd doc list` for the metadata it needs instead.

// The issue status set; the hues match the board's blocked/done colours so an
// issue chip never reads as something new.
var ISSUE_STATUSES = Taxonomy.makeTaxonomy([
  { id: "open", label: "Open", color: "#e8954a" },
  { id: "closed", label: "Closed", color: "#7fb069" }
])

var issueStatusLabel = ISSUE_STATUSES.label
var issueStatusColor = ISSUE_STATUSES.color

function str(value) {
  return value === undefined || value === null ? "" : String(value)
}

// entityId -> comments, oldest first. brd already returns them oldest first;
// a missing/garbage created_at sorts last rather than throwing off the order.
// Equal timestamps (brd writes whole seconds, so a burst of comments shares
// one) keep the order they were exported in: the comparator breaks the tie on
// the original index itself rather than trusting the engine's sort to be stable.
function indexComments(data) {
  var map = {}
  ;((data || {}).comments || []).forEach(function(c) {
    if (!c || !c.entity_id) return
    var entityId = String(c.entity_id)
    if (!map[entityId]) map[entityId] = []
    map[entityId].push({ id: str(c.id), entityId: entityId, author: str(c.author),
                         body: str(c.body), createdAt: str(c.created_at) })
  })
  Object.keys(map).forEach(function(key) {
    var rows = map[key].map(function(comment, index) { return { index: index, comment: comment } })
    rows.sort(function(a, b) {
      var ta = Date.parse(a.comment.createdAt), tb = Date.parse(b.comment.createdAt)
      if (isNaN(ta) && isNaN(tb)) return a.index - b.index
      if (isNaN(ta)) return 1
      if (isNaN(tb)) return -1
      if (ta !== tb) return ta - tb
      return a.index - b.index
    })
    map[key] = rows.map(function(row) { return row.comment })
  })
  return map
}

// entityId -> { refs, referencedBy }: what it points at, and what points at it.
// EXPLICIT references only. `brd export`'s refs[] carry the refs somebody wrote
// with `--ref` (origin "explicit") and never the origin "link" refs a
// [[wikilink]] in a body creates; those are reported per entity by `brd show`
// and `brd issue list`, which this store does not read for refs.
// tests/contract/test_brd_shapes.py pins that behaviour on the real brd.
function indexRefs(data) {
  var map = {}
  function slot(id) {
    if (!map[id]) map[id] = { refs: [], referencedBy: [] }
    return map[id]
  }
  ;((data || {}).refs || []).forEach(function(r) {
    if (!r || !r.src_id || !r.dst_id) return
    slot(String(r.src_id)).refs.push(String(r.dst_id))
    slot(String(r.dst_id)).referencedBy.push(String(r.src_id))
  })
  return map
}

// issueId -> the cards it blocks, in card-tree order. The export's issues carry
// no `blocks` (only `brd issue list` does), so the relation is read back off
// the nested `cards[]` tree, where every card -- children included -- carries
// the `blocked_by` ids. Closing an issue leaves its id in blocked_by, which is
// what `brd issue list` reports too, so a closed issue still names its cards.
function indexBlockedCards(data) {
  var map = {}
  function visit(card) {
    if (!card || !card.id) return
    var cardId = String(card.id)
    ;(card.blocked_by || []).forEach(function(blockerId) {
      var key = String(blockerId)
      if (!map[key]) map[key] = []
      if (map[key].indexOf(cardId) < 0) map[key].push(cardId)
    })
    ;(card.children || []).forEach(visit)
  }
  ;((data || {}).cards || []).forEach(visit)
  return map
}

// The Issues list: open first, then closed; each group newest-updated first.
function issueList(data, commentsByEntity) {
  var comments = commentsByEntity || {}
  var blockedCards = indexBlockedCards(data)
  var list = ((data || {}).issues || []).filter(function(i) { return i && i.id }).map(function(i) {
    var id = String(i.id)
    return {
      id: id,
      title: str(i.title) !== "" ? str(i.title) : id,
      body: str(i.body),
      status: i.status === "closed" ? "closed" : "open",
      closeReason: str(i.close_reason),
      blocks: i.blocks ? i.blocks.map(String) : (blockedCards[id] || []),
      createdAt: str(i.created_at),
      updatedAt: str(i.updated_at),
      commentCount: (comments[id] || []).length
    }
  })
  list.sort(function(a, b) {
    if (a.status !== b.status) return a.status === "open" ? -1 : 1
    var ta = Date.parse(a.updatedAt), tb = Date.parse(b.updatedAt)
    if (isNaN(ta) && isNaN(tb)) return a.id < b.id ? -1 : a.id > b.id ? 1 : 0
    if (isNaN(ta)) return 1
    if (isNaN(tb)) return -1
    if (tb !== ta) return tb - ta
    return a.id < b.id ? -1 : a.id > b.id ? 1 : 0
  })
  return list
}

var EXPORT_COLLECTIONS = ["cards", "issues", "documents", "comments", "tags", "refs"]

// brd_export 2 nests the collections per project: { projects: [{ project, cards,
// issues, ... }] }. Plain `brd export` yields exactly one entry (the current
// project); several entries (`--all`) are concatenated. The older flat shape
// (collections at the top level) passes through unchanged.
function flattenExport(data) {
  if (!data || !Array.isArray(data.projects)) return data
  var flat = { brd_export: data.brd_export }
  EXPORT_COLLECTIONS.forEach(function(key) { flat[key] = [] })
  data.projects.forEach(function(entry) {
    if (!entry || typeof entry !== "object") return
    EXPORT_COLLECTIONS.forEach(function(key) {
      if (Array.isArray(entry[key])) flat[key] = flat[key].concat(entry[key])
    })
  })
  return flat
}

// `brd export`'s last stdout line plus its exit code. Anything but a clear
// success is empty extras: an old brd without `export`, a crash or garbage must
// leave the panel exactly as it was, never an error.
function parseExport(stdout, exitCode) {
  var empty = { ok: false, issues: [], commentsByEntity: {}, refsByEntity: {}, error: "" }
  var result = Results.parseJsonLine(stdout, exitCode, "Could not read this project's extras.")
  if (!result.ok) return { ok: false, issues: [], commentsByEntity: {}, refsByEntity: {}, error: result.error }
  var data = result.data.data
  if (!data || typeof data !== "object" || Array.isArray(data)) return empty
  data = flattenExport(data)
  var commentsByEntity = indexComments(data)
  return { ok: true, issues: issueList(data, commentsByEntity), commentsByEntity: commentsByEntity,
           refsByEntity: indexRefs(data), error: "" }
}

// An empty/undefined status means "all".
function filterIssues(list, statusId) {
  return ISSUE_STATUSES.filter(list, "status", statusId)
}

function searchIssues(list, query) {
  return (list || []).filter(function(i) {
    return Text.matchesQuery(i.title, query) || Text.matchesQuery(i.body, query) || Text.matchesQuery(i.id, query)
  })
}

function issueStatusCounts(list) {
  return ISSUE_STATUSES.counts(list, "status")
}

// The clickable rows of an issue's detail view, in display order. A target that
// is neither a card of this board nor a known issue cannot be opened, so it is
// not listed (the same rule board.js detailLinks() follows).
function issueDetailLinks(issue, cardMap, issueMap, refsByEntity) {
  if (!issue) return []
  var cards = cardMap || {}
  var issues = issueMap || {}
  var links = []
  ;(issue.blocks || []).forEach(function(id) {
    if (cards[id]) links.push({ section: "blocks", id: id })
  })
  var refs = (refsByEntity || {})[issue.id] || { refs: [], referencedBy: [] }
  refs.refs.forEach(function(id) {
    if (cards[id] || issues[id]) links.push({ section: "ref", id: id })
  })
  refs.referencedBy.forEach(function(id) {
    if (cards[id] || issues[id]) links.push({ section: "referenced_by", id: id })
  })
  return links
}

function blocksLabel(count) {
  var n = Number(count) || 0
  return n <= 0 ? "" : "blocks " + n + (n === 1 ? " card" : " cards")
}

function commentCountLabel(count) {
  var n = Number(count) || 0
  return n <= 0 ? "" : n + (n === 1 ? " comment" : " comments")
}

// "just now" / "5m ago" / "3h ago" / "2d ago", then the plain date. A
// timestamp brd did not write (or did not write as a date) is shown as it is.
function relativeTime(iso, nowMs) {
  var text = str(iso)
  if (text === "") return ""
  var then = Date.parse(text)
  if (isNaN(then)) return text
  var now = Number(nowMs)
  if (isNaN(now)) now = Date.now()
  var seconds = Math.floor((now - then) / 1000)
  if (seconds < 0) return text.slice(0, 10)
  if (seconds < 60) return "just now"
  if (seconds < 3600) return Math.floor(seconds / 60) + "m ago"
  if (seconds < 86400) return Math.floor(seconds / 3600) + "h ago"
  if (seconds < 7 * 86400) return Math.floor(seconds / 86400) + "d ago"
  return text.slice(0, 10)
}

// `brd doc list`'s last stdout line plus its exit code. source_path is
// relative to the project root -- that is what the listing is matched on.
function parseDocList(stdout, exitCode) {
  var result = Results.parseJsonLine(stdout, exitCode, "Could not list brd's documents.")
  if (!result.ok) return { ok: false, registered: [], error: result.error }
  var rows = Array.isArray(result.data.data) ? result.data.data : []
  return {
    ok: true,
    // A source_path is joined onto the project root to open the file, so one
    // that leaves the project (absolute, or with a `..` segment) is not a
    // document of this project: it is dropped rather than shown or opened.
    registered: rows.filter(function(d) {
      return d && d.source_path && Documents.isInsideProject(d.source_path)
    }).map(function(d) {
      return { id: str(d.id), title: str(d.title), sourcePath: String(d.source_path),
               sourceState: str(d.source_state) !== "" ? str(d.source_state) : "ok",
               tags: (d.tags || []).map(String), createdAt: str(d.created_at), updatedAt: str(d.updated_at) }
    }),
    error: ""
  }
}
