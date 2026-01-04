import deep_heating/ui/model.{type Model}
import deep_heating/ui/msg.{type Msg}
import gleam/option.{None, Some}
import lustre/attribute.{class}
import lustre/element.{type Element, text}
import lustre/element/html.{div, h1, p}

/// Render the main view from the model.
pub fn view(model: Model) -> Element(Msg) {
  div([class("container mx-auto p-4")], [
    h1([class("text-2xl font-bold mb-4")], [text("Deep Heating")]),
    case model.connected {
      True -> connected_view(model)
      False -> disconnected_view()
    },
  ])
}

fn connected_view(model: Model) -> Element(Msg) {
  case model.state {
    None -> loading_view()
    Some(_state) -> {
      // TODO: Render room cards
      div([], [p([], [text("Connected - Rooms will be displayed here")])])
    }
  }
}

fn disconnected_view() -> Element(Msg) {
  div([class("alert alert-warning")], [
    text("Connecting to server..."),
  ])
}

fn loading_view() -> Element(Msg) {
  div([class("loading loading-spinner loading-lg")], [])
}
