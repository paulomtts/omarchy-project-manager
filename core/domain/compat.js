.pragma library

// Whether v is an array. Qt 6.12 hands an array that crossed a QML `var`
// property or function argument over as a V4Sequence, which has map, length
// and indexing but for which Array.isArray is false; every place that guards
// on "is this a list" asks here instead.
function isArray(v) {
  return Array.isArray(v) || Object.prototype.toString.call(v) === "[object V4Sequence]"
}

// JSON.stringify with every object's keys in sorted order. Qt 6.12 reorders the
// keys of an object that crossed a QML property, so the order a payload is
// written in must not depend on the Qt version.
function stringify(value) {
  return JSON.stringify(_sorted(value))
}

function _sorted(v) {
  if (isArray(v)) {
    var list = []
    for (var i = 0; i < v.length; i++) list.push(_sorted(v[i]))
    return list
  }
  if (v === null || typeof v !== "object") return v
  var out = {}
  var keys = Object.keys(v).sort()
  for (var k = 0; k < keys.length; k++) out[keys[k]] = _sorted(v[keys[k]])
  return out
}
