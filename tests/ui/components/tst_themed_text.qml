import QtQuick
import QtTest
import qs.Commons
import qs.Commons as Cm
import "../../../ui/components" as UI
import "../../../ui/theme" as T

TestCase {
  id: tc
  name: "ThemedText"
  width: 300; height: 200

  T.Theme { id: tcTheme; foreground: "#00ff00"; fontFamily: "mono" }

  Component { id: plainC; UI.ThemedText { text: "hi" } }
  Component { id: themedC; UI.ThemedText { theme: tcTheme; text: "hi" } }
  Component { id: overriddenC; UI.ThemedText { theme: tcTheme; text: "hi"; color: "#0000ff" } }

  function make(variant) {
    var item = createTemporaryObject(themedC, tc)
    if (variant !== undefined) item.variant = variant
    return item
  }

  function test_it_defaults_to_the_body_variant_in_the_themes_colours() {
    var item = make()
    compare(item.variant, "body")
    compare(item.color, Qt.color("#00ff00"))
    compare(item.font.family, "mono")
    compare(item.font.pixelSize, Style.font.body)
  }

  function test_the_caption_variant_is_dim_and_small() {
    var item = make("caption")
    compare(String(item.color), String(tcTheme.dim))
    compare(item.font.pixelSize, Style.font.caption)
  }

  function test_the_dim_variant_keeps_the_body_size() {
    var item = make("dim")
    compare(String(item.color), String(tcTheme.dim))
    compare(item.font.pixelSize, Style.font.body)
  }

  function test_the_heading_variant_is_the_foreground_at_the_heading_size() {
    var item = make("heading")
    compare(item.color, Qt.color("#00ff00"))
    compare(item.font.pixelSize, Style.font.heading)
  }

  function test_the_small_variant_is_the_foreground_at_the_body_small_size() {
    var item = make("small")
    compare(item.color, Qt.color("#00ff00"))
    compare(item.font.pixelSize, Style.font.bodySmall)
  }

  function test_a_caller_may_override_the_colour() {
    var item = createTemporaryObject(overriddenC, tc)
    compare(item.color, Qt.color("#0000ff"))
    compare(item.font.family, "mono")
  }

  function test_without_a_theme_it_uses_the_shell_defaults() {
    var item = createTemporaryObject(plainC, tc)
    compare(item.color, Cm.Color.foreground)
    compare(item.font.family, Style.font.family)
    compare(item.font.pixelSize, Style.font.body)
  }
}
