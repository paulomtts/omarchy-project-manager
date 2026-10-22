.pragma library
.import "results.js" as Results
.import "taxonomy.js" as Taxonomy
.import "text.js" as Text
.import "compat.js" as Compat

var MAX_DOC_BYTES = 1048576

// The Documents badges: a fixed set, in display order. list-docs.py assigns
// each document one of these ids. The colours are fixed hues (the shell theme
// has no palette for this), distinct from the status colours so a category
// badge never reads as a card status; "other" takes the caller's neutral one.
var DOC_TYPES = Taxonomy.makeTaxonomy([
  { id: "architecture", label: "Architecture", color: "#b39ddb" },
  { id: "specs", label: "Specs", color: "#5fa8d3" },
  { id: "standards", label: "Standards", color: "#4db6ac" },
  { id: "audits", label: "Audits", color: "#e2c15a" },
  { id: "other", label: "Other" }
])

var DOC_CATEGORIES = DOC_TYPES.items
var docCategoryLabel = DOC_TYPES.label
var docCategoryColor = DOC_TYPES.color

// An empty/undefined category means "all".
function filterDocsByCategory(docs, categoryId) {
  return DOC_TYPES.filter(docs, "category", categoryId)
}

// [{ id, label, count }] for the categories that have at least one document.
function docCategoryCounts(docs) {
  return DOC_TYPES.counts(docs, "category")
}

function filterDocs(docs, query) {
  return (docs || []).filter(function(d) {
    return Text.matchesQuery(d.title, query) || Text.matchesQuery(d.path, query)
  })
}

// list-docs.py's last stdout line plus its exit code, as
// { ok, docs, truncated, error }. Anything but a clear success is a failure.
function parseDocsResult(stdout, exitCode) {
  var result = Results.parseJsonLine(stdout, exitCode, "Could not list documents.")
  if (result.ok)
    return { ok: true, docs: Compat.isArray(result.data.docs) ? result.data.docs : [],
             truncated: result.data.truncated === true, error: "" }
  return { ok: false, docs: [], truncated: false, error: result.error }
}

// brd can register a project's Markdown files and keep a backup of each. The
// listing and the registrations are matched on the path relative to the project
// root -- the same string both sides use. A registration whose file the listing
// does not have (deleted, or outside docs/) is still listed, dimmed, so its
// backup stays discoverable.
function mergeRegistered(docs, registered) {
  var rows = (docs || []).map(function(d) {
    var copy = {}
    Object.keys(d).forEach(function(key) { copy[key] = d[key] })
    copy.brd = null
    return copy
  })
  var seen = {}
  rows.forEach(function(row) { seen[row.path] = row })
  ;(registered || []).forEach(function(entry) {
    var brd = { id: entry.id, title: entry.title, sourceState: entry.sourceState, tags: entry.tags || [] }
    if (seen[entry.sourcePath]) { seen[entry.sourcePath].brd = brd; return }
    rows.push({ path: entry.sourcePath, title: entry.title !== "" ? entry.title : entry.sourcePath,
                size: 0, category: "other", missing: true, brd: brd })
  })
  return rows
}

// What a row and the open document's header say about brd's backup: nothing at
// all when brd does not know the file, and the state itself when brd's copy no
// longer matches what is on disk.
function brdStateLabel(entry) {
  if (!entry || !entry.brd) return ""
  return entry.brd.sourceState === "ok" ? "Registered in brd" : "Registered in brd · " + entry.brd.sourceState
}

// A path is inside the project when it is relative and no segment is `..`.
// Both separators are checked: brd stores what it was given, and a Windows-style
// `docs\..\..\etc` must not slip past a `/`-only test.
function isInsideProject(relPath) {
  var text = String(relPath === undefined || relPath === null ? "" : relPath)
  if (text === "" || text.charAt(0) === "/" || text.charAt(0) === "\\") return false
  if (/^[A-Za-z]:/.test(text)) return false
  var parts = text.split(/[\/\\]/)
  for (var i = 0; i < parts.length; i++) if (parts[i] === "..") return false
  return true
}

// The absolute path of a document of this project. A path that would leave the
// project (absolute, or with a `..` segment) resolves to nothing rather than to
// a file outside it -- the last line of defence behind parseDocList().
function docAbsolutePath(rootPath, relPath) {
  if (!isInsideProject(relPath)) return ""
  return String(rootPath).replace(/\/+$/, "") + "/" + relPath
}

function docTooLarge(size) {
  return size > MAX_DOC_BYTES
}

// Documents may open with a YAML frontmatter block (list-docs.py reads its
// `tag:`); it is metadata, so the rendered document leaves it out.
function stripFrontmatter(text) {
  var value = String(text === undefined || text === null ? "" : text)
  var m = /^---[ \t]*\r?\n[\s\S]*?\r?\n---[ \t]*(?:\r?\n|$)/.exec(value)
  return m ? value.slice(m[0].length) : value
}

// set-doc-tag.py's answer (its last stdout line) plus its exit code, as
// { ok, error }. Anything but a clear success is a failure.
function parseTagResult(stdout, exitCode) {
  var result = Results.parseJsonLine(stdout, exitCode, "Could not change the document type.")
  if (result.ok) return { ok: true, error: "" }
  return { ok: false, error: result.error }
}
