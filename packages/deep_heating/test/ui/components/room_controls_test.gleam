import birdie
import deep_heating/ui/components/room_controls
import lustre/dev/query
import lustre/element
import ui/test_helpers

// =============================================================================
// Snapshot Tests
// =============================================================================

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

pub fn room_controls_sleeping_mode_test() {
  let room = test_helpers.sleeping_room()
  room_controls.view(room)
  |> element.to_string()
  |> birdie.snap("room_controls_sleeping_mode")
}

pub fn room_controls_positive_adjustment_test() {
  let room = test_helpers.adjusted_room(1.0)
  room_controls.view(room)
  |> element.to_string()
  |> birdie.snap("room_controls_positive_adjustment")
}

pub fn room_controls_negative_adjustment_test() {
  let room = test_helpers.adjusted_room(-0.5)
  room_controls.view(room)
  |> element.to_string()
  |> birdie.snap("room_controls_negative_adjustment")
}

pub fn room_controls_no_target_test() {
  let room = test_helpers.room_without_target()
  room_controls.view(room)
  |> element.to_string()
  |> birdie.snap("room_controls_no_target")
}

// =============================================================================
// Query Tests - Conditional Rendering
// =============================================================================

pub fn auto_mode_has_buttons_test() {
  let view = room_controls.view(test_helpers.heating_room())
  let assert True =
    query.has(view, query.attribute("data-testid", "colder-button"))
  let assert True =
    query.has(view, query.attribute("data-testid", "warmer-button"))
}

pub fn off_mode_has_no_buttons_test() {
  let view = room_controls.view(test_helpers.off_room())
  let assert False =
    query.has(view, query.attribute("data-testid", "colder-button"))
  let assert False =
    query.has(view, query.attribute("data-testid", "warmer-button"))
}

pub fn sleeping_mode_has_no_buttons_test() {
  let view = room_controls.view(test_helpers.sleeping_room())
  let assert False =
    query.has(view, query.attribute("data-testid", "colder-button"))
  let assert False =
    query.has(view, query.attribute("data-testid", "warmer-button"))
}

pub fn no_adjustment_has_no_badge_test() {
  let view = room_controls.view(test_helpers.heating_room())
  let assert False =
    query.has(view, query.attribute("data-testid", "adjustment-badge"))
}

pub fn positive_adjustment_shows_badge_test() {
  let view = room_controls.view(test_helpers.adjusted_room(1.0))
  let assert True =
    query.has(view, query.attribute("data-testid", "adjustment-badge"))
}

pub fn negative_adjustment_shows_badge_test() {
  let view = room_controls.view(test_helpers.adjusted_room(-0.5))
  let assert True =
    query.has(view, query.attribute("data-testid", "adjustment-badge"))
}

pub fn always_has_target_display_test() {
  let view = room_controls.view(test_helpers.heating_room())
  let assert True =
    query.has(view, query.attribute("data-testid", "target-display"))

  let view_off = room_controls.view(test_helpers.off_room())
  let assert True =
    query.has(view_off, query.attribute("data-testid", "target-display"))
}
