import deep_heating/ui/model.{type Model, Model}
import deep_heating/ui/msg.{
  type Msg, AdjustRoom, Connected, Disconnected, StateReceived,
}
import gleam/option.{Some}

/// Update the model in response to a message.
pub fn update(model: Model, msg: Msg) -> Model {
  case msg {
    Connected -> Model(..model, connected: True)
    Disconnected -> Model(..model, connected: False)
    StateReceived(state) -> Model(..model, state: Some(state))
    AdjustRoom(_room_name, _delta) -> {
      // TODO: Send adjustment to server
      model
    }
  }
}
