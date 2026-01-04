import lustre/attribute.{class}
import lustre/element.{type Element, text}
import lustre/element/html.{div, span}

/// Render the connection overlay. When disconnected, shows a full-screen
/// overlay with a loading spinner. When connected, renders nothing.
pub fn view(connected: Bool) -> Element(msg) {
  case connected {
    True -> element.none()
    False -> overlay("Connecting...", "connection-overlay")
  }
}

fn overlay(message: String, test_id: String) -> Element(msg) {
  div(
    [
      class("fixed inset-0 bg-black/50 flex items-center justify-center z-50"),
      attribute.attribute("data-testid", test_id),
    ],
    [
      div([class("flex flex-col items-center gap-4")], [
        spinner(),
        div([class("text-white text-lg")], [text(message)]),
      ]),
    ],
  )
}

fn spinner() -> Element(msg) {
  span(
    [
      class("loading loading-spinner loading-lg text-primary"),
      attribute.attribute("data-testid", "spinner"),
    ],
    [],
  )
}
