import QtQuick
import qs.Commons
import qs.Commons as Cm
import qs.Ui
import "../theme" as T

// The shell's Button with the style every action in the panel repeats: a
// bordered small button in the theme's font, urgent-coloured when it is
// destructive, dimmed while disabled.
Button {
  id: button

  // The owner's Theme, or none: `palette` then falls back to the button's own.
  // Both are objects, and tearing a view down nulls them while the bindings
  // below still run once, so every read of `palette` is guarded; the guard's
  // value is never painted.
  property var theme: null
  property string tone: "normal"

  readonly property var palette: button.theme || buttonTheme

  bordered: true
  foreground: !button.palette ? Cm.Color.foreground
    : button.tone === "danger" ? button.palette.urgent : button.palette.foreground
  fontFamily: button.palette ? button.palette.fontFamily : Style.font.family
  fontSize: Style.font.bodySmall
  verticalPadding: Style.spacing.controlPaddingY
  opacity: button.enabled ? 1 : 0.5

  T.Theme { id: buttonTheme }
}
