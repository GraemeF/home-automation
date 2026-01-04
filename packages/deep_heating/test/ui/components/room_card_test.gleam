import birdie
import deep_heating/ui/components/room_card
import lustre/element
import ui/test_helpers

pub fn room_card_heating_test() {
  let room = test_helpers.heating_room()
  room_card.view(room)
  |> element.to_string()
  |> birdie.snap("room_card_heating")
}

pub fn room_card_cooling_test() {
  let room = test_helpers.cooling_room()
  room_card.view(room)
  |> element.to_string()
  |> birdie.snap("room_card_cooling")
}
