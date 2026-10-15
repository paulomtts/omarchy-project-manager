.pragma library

// A colour token the theme may not define yet: the theme's value when the
// theme is an object and reading `name` on it gives something, else
// `fallback`. A defined token always wins, whatever its value. A null theme
// (a view being torn down) gives the fallback rather than throwing.
function token(theme, name, fallback) {
  if (!theme) return fallback
  var value = theme[name]
  return value === undefined ? fallback : value
}
