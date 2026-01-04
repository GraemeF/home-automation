import birdie
import deep_heating/ui/model.{Model}
import deep_heating/ui/view
import gleam/option.{None, Some}
import lustre/dev/query
import lustre/element
import ui/test_helpers

// ============================================================================
// Snapshot Tests
// ============================================================================

pub fn view_disconnected_test() {
  let model = Model(connected: False, state: None)
  view.view(model)
  |> element.to_string()
  |> birdie.snap("main_view_disconnected")
}

pub fn view_connected_no_state_test() {
  let model = Model(connected: True, state: None)
  view.view(model)
  |> element.to_string()
  |> birdie.snap("main_view_loading")
}

pub fn view_connected_with_state_test() {
  let model = Model(connected: True, state: Some(test_helpers.sample_state()))
  view.view(model)
  |> element.to_string()
  |> birdie.snap("main_view_with_rooms")
}

pub fn view_heating_active_test() {
  let model =
    Model(connected: True, state: Some(test_helpers.state_heating_active()))
  view.view(model)
  |> element.to_string()
  |> birdie.snap("main_view_heating_active")
}

pub fn view_multiple_rooms_sorted_test() {
  let model =
    Model(
      connected: True,
      state: Some(test_helpers.state_with_multiple_rooms()),
    )
  view.view(model)
  |> element.to_string()
  |> birdie.snap("main_view_rooms_sorted_by_temp")
}

// ============================================================================
// Query Tests - Structural
// ============================================================================

pub fn app_root_has_test_id_test() {
  let model = Model(connected: True, state: None)
  let v = view.view(model)
  let assert True = query.has(v, query.attribute("data-testid", "app-root"))
}

pub fn main_content_has_test_id_test() {
  let model = Model(connected: True, state: None)
  let v = view.view(model)
  let assert True = query.has(v, query.attribute("data-testid", "main-content"))
}

// ============================================================================
// Query Tests - Connection Overlay
// ============================================================================

pub fn disconnected_shows_overlay_test() {
  let model = Model(connected: False, state: None)
  let v = view.view(model)
  let assert True =
    query.has(v, query.attribute("data-testid", "connection-overlay"))
}

pub fn connected_no_overlay_test() {
  let model = Model(connected: True, state: None)
  let v = view.view(model)
  let assert False =
    query.has(v, query.attribute("data-testid", "connection-overlay"))
}

// ============================================================================
// Query Tests - Loading State
// ============================================================================

pub fn loading_state_shows_placeholder_test() {
  let model = Model(connected: True, state: None)
  let v = view.view(model)
  let assert True =
    query.has(v, query.attribute("data-testid", "loading-placeholder"))
  let assert False = query.has(v, query.attribute("data-testid", "home-view"))
}

pub fn loading_placeholder_has_spinner_test() {
  let model = Model(connected: True, state: None)
  let v = view.view(model)
  let assert True = query.has(v, query.class("loading-spinner"))
}

// ============================================================================
// Query Tests - Home View with State
// ============================================================================

pub fn with_state_shows_home_view_test() {
  let model = Model(connected: True, state: Some(test_helpers.sample_state()))
  let v = view.view(model)
  let assert False =
    query.has(v, query.attribute("data-testid", "loading-placeholder"))
  let assert True = query.has(v, query.attribute("data-testid", "home-view"))
}

pub fn rooms_grid_present_test() {
  let model = Model(connected: True, state: Some(test_helpers.sample_state()))
  let v = view.view(model)
  let assert True = query.has(v, query.attribute("data-testid", "rooms-grid"))
}

pub fn rooms_grid_has_flex_class_test() {
  let model = Model(connected: True, state: Some(test_helpers.sample_state()))
  let v = view.view(model)
  let assert Ok(grid) =
    query.find(v, query.element(query.attribute("data-testid", "rooms-grid")))
  let assert True = query.has(grid, query.class("flex-wrap"))
}

// ============================================================================
// Query Tests - Room Cards
// ============================================================================

pub fn rooms_rendered_as_cards_test() {
  let state = test_helpers.state_with_multiple_rooms()
  let model = Model(connected: True, state: Some(state))
  let v = view.view(model)
  // Should have room cards
  let assert True = query.has(v, query.attribute("data-testid", "room-card"))
}

// ============================================================================
// Query Tests - Heating Badge
// ============================================================================

pub fn heating_badge_shown_when_heating_test() {
  let model =
    Model(connected: True, state: Some(test_helpers.state_heating_active()))
  let v = view.view(model)
  // Badge should show "Heating" text
  let assert True = query.has(v, query.text("Heating"))
}

pub fn heating_badge_shows_idle_when_not_heating_test() {
  let model = Model(connected: True, state: Some(test_helpers.sample_state()))
  let v = view.view(model)
  // Badge should show "Idle" text (sample_state has is_heating = Some(False))
  let assert True = query.has(v, query.text("Idle"))
}

// ============================================================================
// Query Tests - Breadcrumbs
// ============================================================================

pub fn breadcrumbs_present_test() {
  let model = Model(connected: True, state: None)
  let v = view.view(model)
  let assert True = query.has(v, query.class("breadcrumbs"))
}

pub fn breadcrumbs_has_deep_heating_link_test() {
  let model = Model(connected: True, state: None)
  let v = view.view(model)
  let assert True = query.has(v, query.text("Deep Heating"))
}
