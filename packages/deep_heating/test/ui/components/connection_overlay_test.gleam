import birdie
import deep_heating/ui/components/connection_overlay
import lustre/dev/query
import lustre/element

// ============================================================================
// Snapshot Tests
// ============================================================================

pub fn connection_overlay_when_connected_test() {
  connection_overlay.view(True)
  |> element.to_string()
  |> birdie.snap("connection_overlay_when_connected")
}

pub fn connection_overlay_when_disconnected_test() {
  connection_overlay.view(False)
  |> element.to_string()
  |> birdie.snap("connection_overlay_when_disconnected")
}

// ============================================================================
// Query Tests
// ============================================================================

pub fn connected_renders_empty_test() {
  let view = connection_overlay.view(True)
  let assert "" = element.to_string(view)
}

pub fn disconnected_has_overlay_test() {
  let view = connection_overlay.view(False)
  let assert True =
    query.has(view, query.attribute("data-testid", "connection-overlay"))
}

pub fn disconnected_has_spinner_test() {
  let view = connection_overlay.view(False)
  let assert True = query.has(view, query.attribute("data-testid", "spinner"))
}

pub fn disconnected_has_loading_spinner_class_test() {
  let view = connection_overlay.view(False)
  let assert True = query.has(view, query.class("loading-spinner"))
}

pub fn disconnected_has_z50_for_overlay_test() {
  let view = connection_overlay.view(False)
  let assert True = query.has(view, query.class("z-50"))
}

pub fn disconnected_has_fixed_position_test() {
  let view = connection_overlay.view(False)
  let assert True = query.has(view, query.class("fixed"))
}

pub fn disconnected_shows_connecting_text_test() {
  let view = connection_overlay.view(False)
  let assert True = query.has(view, query.text("Connecting..."))
}
