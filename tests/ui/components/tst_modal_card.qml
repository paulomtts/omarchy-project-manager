import QtQuick
import QtTest
import qs.Commons
import qs.Commons as Cm
import "../../helpers/find.js" as H
import "../../../ui/components" as UI

TestCase {
  id: tc
  name: "ModalCard"
  when: windowShown
  visible: true
  width: 600; height: 400

  Component {
    id: cardC
    UI.ModalCard {
      width: 560; height: 360
      maxWidth: Style.space(440)
      Rectangle { objectName: "cardBody"; width: parent.width; height: 40; color: "#123456" }
    }
  }
  SignalSpy { id: dismissals; signalName: "dismissed" }

  function make() {
    var modal = createTemporaryObject(cardC, tc)
    dismissals.target = modal
    dismissals.clear()
    return modal
  }

  function test_it_is_hidden_until_shown() {
    var modal = make()
    compare(modal.visible, false)
    modal.shown = true
    compare(modal.visible, true)
  }

  function test_the_card_sits_on_a_dimmed_backdrop_and_is_narrower_than_the_modal() {
    var modal = make()
    modal.shown = true
    var backdrop = H.find(modal, "modalBackdrop")
    verify(backdrop, "backdrop")
    compare(backdrop.color, Qt.rgba(0, 0, 0, 0.55))
    compare(backdrop.width, modal.width)
    var card = H.find(modal, "modalCard")
    verify(card, "card")
    compare(card.width, Math.min(Style.space(440), modal.width - Style.space(48)))
    compare(card.radius, Style.space(10))
    compare(card.border.width, 1)
    compare(card.color, Cm.Color.popups.background)
    compare(card.border.color, Cm.Color.popups.border)
    verify(card.width < modal.width, "the card is narrower than the modal")
  }

  function test_the_content_goes_inside_the_card() {
    var modal = make()
    modal.shown = true
    var body = H.find(modal, "cardBody")
    verify(body, "content item")
    var card = H.find(modal, "modalCard")
    var inside = false
    for (var it = body; it; it = it.parent) if (it === card) inside = true
    verify(inside, "the content is a descendant of the card")
    verify(card.height > body.height, "the card wraps the content")
  }

  function test_clicking_the_backdrop_dismisses_but_clicking_the_card_does_not() {
    var modal = make()
    modal.shown = true
    mouseClick(H.find(modal, "modalBackdrop"), 2, 2)
    compare(dismissals.count, 1)
    var card = H.find(modal, "modalCard")
    mouseClick(card, 3, 3)
    compare(dismissals.count, 1)
  }

  function test_a_non_dismissable_card_ignores_the_backdrop() {
    var modal = make()
    modal.shown = true
    modal.dismissable = false
    mouseClick(H.find(modal, "modalBackdrop"), 2, 2)
    compare(dismissals.count, 0)
  }

  function test_the_object_names_of_the_backdrop_and_the_card_can_be_set() {
    var modal = make()
    modal.backdropObjectName = "myBackdrop"
    modal.cardObjectName = "myCard"
    modal.shown = true
    verify(H.find(modal, "myBackdrop"), "renamed backdrop")
    verify(H.find(modal, "myCard"), "renamed card")
  }

  function test_the_height_can_be_capped() {
    var modal = make()
    modal.shown = true
    var card = H.find(modal, "modalCard")
    var natural = card.height
    modal.maxHeight = natural - 10
    compare(card.height, natural - 10)
  }
}
