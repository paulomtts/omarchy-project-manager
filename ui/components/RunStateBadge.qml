import QtQuick
import "themeToken.js" as Tokens

// The two run states the Runs row names in words: RUNNING in the accent tint
// and ESCALATED in the warn tint, on the Badge pill. Every other state (parked,
// dead, done, cancelled, anything unknown) shows no badge. No glyph and no
// pulse. Presentation only: `state` (Item's own string property, used as
// plain text) is a Runs.runState name, matched exactly.
Badge {
  id: stateBadge
  objectName: "runStateBadge"
  textObjectName: "runStateBadgeText"

  text: stateBadge.state === "running" ? "RUNNING"
    : stateBadge.state === "escalated" ? "ESCALATED"
    : ""
  tint: stateBadge.state === "escalated" ? Tokens.token(stateBadge.palette, "warn", "#f0b54a")
    : Tokens.token(stateBadge.palette, "accent", "#7ed491")
  visible: stateBadge.text !== ""
}
