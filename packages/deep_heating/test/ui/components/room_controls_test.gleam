import birdie
import deep_heating/ui/components/room_controls
import lustre/element
import ui/test_helpers

pub fn room_controls_auto_mode_test() {
  let room = test_helpers.heating_room()
  room_controls.view(room)
  |> element.to_string()
  |> birdie.snap("room_controls_auto_mode")
}

pub fn room_controls_off_mode_test() {
  let room = test_helpers.off_room()
  room_controls.view(room)
  |> element.to_string()
  |> birdie.snap("room_controls_off_mode")
}
