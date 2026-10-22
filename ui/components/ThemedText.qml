import QtQuick
import qs.Commons
import qs.Commons as Cm
import "../theme" as T

// A Text drawn in the panel's theme. `variant` picks the font size and the
// default colour; it is still a Text, so callers set font.bold, elide,
// wrapMode and textFormat themselves, and override `color` wherever the site
// paints with something other than a plain theme colour (a status tint, a
// per-item colour, `urgent`).
Text {
  id: label

  // The owner's Theme, or none: `palette` then falls back to the label's own.
  // Both are objects and tearing a view down nulls them while these bindings
  // still run once, so every read is guarded; the guard is never painted.
  property var theme: null
  // body | small | caption | heading | dim
  property string variant: "body"

  readonly property var palette: label.theme || labelTheme

  color: !label.palette ? Cm.Color.foreground
    : (label.variant === "caption" || label.variant === "dim") ? label.palette.dim
    : label.palette.foreground
  font.family: label.palette ? label.palette.fontFamily : Style.font.family
  font.pixelSize: !label.palette ? Style.font.body
    : label.variant === "caption" ? label.palette.captionSize
    : label.variant === "heading" ? label.palette.headingSize
    : label.variant === "small" ? label.palette.smallSize
    : label.palette.bodySize

  T.Theme { id: labelTheme }
}
