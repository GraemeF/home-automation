import birdie
import deep_heating/ui/components/room_card
import lustre/element
import ui/test_helpers

// ============================================================================
// Snapshot Tests
// ============================================================================

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

pub fn room_card_no_temperature_test() {
  let room = test_helpers.room_without_temp("Living Room")
  room_card.view(room)
  |> element.to_string()
  |> birdie.snap("room_card_no_temperature")
}

pub fn room_card_no_target_test() {
  let room = test_helpers.room_without_target()
  room_card.view(room)
  |> element.to_string()
  |> birdie.snap("room_card_no_target")
}

pub fn room_card_with_adjustment_test() {
  let room = test_helpers.adjusted_room(1.5)
  room_card.view(room)
  |> element.to_string()
  |> birdie.snap("room_card_with_adjustment")
}

// ============================================================================
// Query Tests
// ============================================================================

import lustre/dev/query

pub fn room_card_has_test_id_test() {
  let view = room_card.view(test_helpers.heating_room())
  let assert True = query.has(view, query.attribute("data-testid", "room-card"))
}

pub fn heating_room_has_fire_icon_test() {
  let view = room_card.view(test_helpers.heating_room())
  let assert True = query.has(view, query.attribute("data-testid", "fire-icon"))
}

pub fn cooling_room_has_no_fire_icon_test() {
  let view = room_card.view(test_helpers.cooling_room())
  let assert False =
    query.has(view, query.attribute("data-testid", "fire-icon"))
}

pub fn room_card_shows_temperature_test() {
  let view = room_card.view(test_helpers.heating_room())
  let assert Ok(temp_elem) =
    query.find(
      view,
      query.element(query.attribute("data-testid", "current-temp")),
    )
  let assert True = query.has(temp_elem, query.text("20.0°C"))
}

pub fn room_card_has_card_class_test() {
  let view = room_card.view(test_helpers.heating_room())
  let assert True = query.has(view, query.class("card"))
}

pub fn heating_room_has_heating_background_test() {
  let view = room_card.view(test_helpers.heating_room())
  let assert True = query.has(view, query.class("bg-heating"))
}

pub fn cooling_room_has_cooling_background_test() {
  let view = room_card.view(test_helpers.cooling_room())
  let assert True = query.has(view, query.class("bg-cooling"))
}

pub fn room_card_shows_room_name_test() {
  let view = room_card.view(test_helpers.heating_room())
  let assert True = query.has(view, query.text("Test Room"))
}

pub fn room_card_has_room_name_data_attribute_test() {
  let view = room_card.view(test_helpers.heating_room())
  let assert True =
    query.has(view, query.attribute("data-room-name", "Test Room"))
}

pub fn room_without_temp_shows_dash_test() {
  let view = room_card.view(test_helpers.room_without_temp("Test Room"))
  let assert Ok(temp_elem) =
    query.find(
      view,
      query.element(query.attribute("data-testid", "current-temp")),
    )
  let assert True = query.has(temp_elem, query.text("–"))
}
