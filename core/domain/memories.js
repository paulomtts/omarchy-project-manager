.pragma library
.import "results.js" as Results
.import "taxonomy.js" as Taxonomy
.import "text.js" as Text
.import "compat.js" as Compat

// ---- Memories: a project's Claude Code memory notes (list-memories.py / memory-op.py)

var MEMORY_TYPE_SET = Taxonomy.makeTaxonomy([
  { id: "user", label: "User", color: "#d98cb3" },
  { id: "feedback", label: "Feedback", color: "#6fb7c9" },
  { id: "project", label: "Project", color: "#9bbf6a" },
  { id: "reference", label: "Reference", color: "#b39ddb" },
  { id: "other", label: "Other" }
])

var MEMORY_TYPES = MEMORY_TYPE_SET.items
var memoryTypeLabel = MEMORY_TYPE_SET.label
var memoryTypeColor = MEMORY_TYPE_SET.color

function filterMemoriesByType(notes, typeId) {
  return MEMORY_TYPE_SET.filter(notes, "type", typeId)
}

function memoryTypeCounts(notes) {
  return MEMORY_TYPE_SET.counts(notes, "type")
}

function filterMemories(notes, query) {
  return (notes || []).filter(function(n) {
    return Text.matchesQuery(n.name, query) || Text.matchesQuery(n.description, query)
      || Text.matchesQuery(n.file, query)
  })
}

// list-memories.py's answer as { ok, found, memoryDir, notes, error }. A
// payload without a notes array is not a usable listing, so it fails too.
function parseMemoriesResult(stdout, exitCode) {
  var generic = "Could not read this project's memories."
  var result = Results.parseJsonLine(stdout, exitCode, generic)
  if (!result.ok || !Compat.isArray(result.data.notes)) {
    var data = result.data
    var message = data && typeof data.error === "string" && data.error !== "" ? data.error : generic
    return { ok: false, found: false, memoryDir: "", notes: [], error: message }
  }
  return { ok: true, found: result.data.found === true,
           memoryDir: String(result.data.memory_dir || ""),
           notes: result.data.notes, error: "" }
}

function parseMemoryOpResult(stdout, exitCode) {
  var result = Results.parseJsonLine(stdout, exitCode, "Could not update the memory.")
  if (result.ok) return { ok: true, backup: String(result.data.backup || ""), error: "" }
  return { ok: false, backup: "", error: result.error }
}

function memoryAbsolutePath(memoryDir, file) {
  return String(memoryDir).replace(/\/+$/, "") + "/" + file
}

// "<type>_<slug>.md", made unique against the files already in the folder.
function newMemoryFile(type, name, existingFiles) {
  var kind = MEMORY_TYPE_SET.ids.indexOf(type) >= 0 ? type : "other"
  var slug = String(name || "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "")
  if (slug === "") slug = "memory"
  var taken = {}
  ;(existingFiles || []).forEach(function(f) { taken[f] = true })
  var base = kind + "_" + slug
  var candidate = base + ".md"
  for (var n = 2; taken[candidate]; n++) candidate = base + "-" + n + ".md"
  return candidate
}

function yamlValue(text) {
  var value = String(text === undefined || text === null ? "" : text).replace(/\s*[\r\n]+\s*/g, " ").trim()
  var risky = /: |#|^[\-?:,\[\]{}&*!|>'"%@`]|["\\]|\s$/.test(value)
  return risky ? '"' + value.replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"' : value
}

// A new note in Claude Code's memory format.
function composeMemory(name, description, type, body) {
  return "---\nname: " + yamlValue(name) + "\ndescription: " + yamlValue(description)
    + "\nmetadata:\n  type: " + type + "\n---\n\n" + String(body || "")
}
