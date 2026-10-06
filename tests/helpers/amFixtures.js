.pragma library

// A fresh parse of tests/fixtures/am/<name> on every call, resolved against
// this file. Throws Error("amFixtures: cannot load <name>: <cause>") when the
// file cannot be read or parsed. Needs QML_XHR_ALLOW_FILE_READ=1.
function load(name) {
  var cause
  try {
    var xhr = new XMLHttpRequest()
    xhr.open("GET", Qt.resolvedUrl("../fixtures/am/" + name), false)
    xhr.send()
    if ((xhr.status === 0 || xhr.status === 200) && xhr.responseText !== "")
      return JSON.parse(xhr.responseText)
    cause = "not readable"
  } catch (e) {
    cause = e.message
  }
  throw new Error("amFixtures: cannot load " + name + ": " + cause)
}
