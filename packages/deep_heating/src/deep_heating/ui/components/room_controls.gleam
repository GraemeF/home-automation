import deep_heating/state.{type RoomState}
import deep_heating/ui/msg.{type Msg}
import lustre/attribute.{class}
import lustre/element.{type Element, text}
import lustre/element/html.{div}

/// Room temperature adjustment controls.
pub fn view(_room: RoomState) -> Element(Msg) {
  // TODO: Implement temperature adjustment buttons
  div([class("flex items-center gap-2")], [
    text("Controls placeholder"),
  ])
}
