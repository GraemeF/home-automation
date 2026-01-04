import deep_heating/state.{type RoomState}
import deep_heating/ui/msg.{type Msg}
import lustre/attribute.{class}
import lustre/element.{type Element, text}
import lustre/element/html.{div}

/// Room card component displaying room temperature and controls.
pub fn view(_room: RoomState) -> Element(Msg) {
  // TODO: Implement full room card
  div([class("card card-compact bg-base-200 shadow-md")], [
    div([class("card-body")], [
      text("Room card placeholder"),
    ]),
  ])
}
