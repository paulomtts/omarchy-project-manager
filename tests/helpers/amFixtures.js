.pragma library

// A fresh parse of tests/fixtures/am/<name> on every call, resolved against
// this file. Needs QML_XHR_ALLOW_FILE_READ=1.
function load(name) {
  var xhr = new XMLHttpRequest()
  xhr.open("GET", Qt.resolvedUrl("../fixtures/am/" + name), false)
  xhr.send()
  return JSON.parse(xhr.responseText)
}
