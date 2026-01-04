import deep_heating/state
import deep_heating/ui/model.{type Model, Model}
import deep_heating/ui/msg.{
  type Msg, AdjustRoom, Connected, Disconnected, StateReceived,
}
import gleam/float
import gleam/list
import gleam/option.{Some}
import lustre/effect.{type Effect}

/// Dependencies for the update function.
/// This allows injection of actor communication for testing.
pub type Dependencies {
  Dependencies(
    /// Callback to adjust a room's temperature target.
    /// Takes room name and the NEW adjustment value (not delta).
    adjust_room: fn(String, Float) -> Nil,
  )
}

/// Create a no-op dependencies instance for testing or simple usage.
pub fn no_op_dependencies() -> Dependencies {
  Dependencies(adjust_room: fn(_, _) { Nil })
}

/// Create an update function with the given dependencies.
/// This factory pattern allows injecting actor communication.
pub fn make_update(
  deps: Dependencies,
) -> fn(Model, Msg) -> #(Model, Effect(Msg)) {
  fn(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
    update_with_deps(model, msg, deps)
  }
}

/// Update the model in response to a message (with dependencies).
fn update_with_deps(
  model: Model,
  msg: Msg,
  deps: Dependencies,
) -> #(Model, Effect(Msg)) {
  case msg {
    Connected -> #(Model(..model, connected: True), effect.none())
    Disconnected -> #(Model(..model, connected: False), effect.none())
    StateReceived(state) -> #(Model(..model, state: Some(state)), effect.none())
    AdjustRoom(room_name, delta) -> {
      // Calculate the new adjustment value
      let new_adjustment = calculate_new_adjustment(model, room_name, delta)
      // Create an effect to send the adjustment to the room actor
      let eff =
        effect.from(fn(_dispatch) {
          deps.adjust_room(room_name, new_adjustment)
        })
      #(model, eff)
    }
  }
}

/// Calculate the new adjustment value for a room.
/// Finds the room's current adjustment and adds the delta.
fn calculate_new_adjustment(
  model: Model,
  room_name: String,
  delta: Float,
) -> Float {
  let current =
    model.state
    |> option.map(fn(s) { find_room_adjustment(s, room_name) })
    |> option.flatten
    |> option.unwrap(0.0)

  clamp_adjustment(current +. delta)
}

/// Find a room's current adjustment from the state.
fn find_room_adjustment(
  deep_state: state.DeepHeatingState,
  room_name: String,
) -> option.Option(Float) {
  deep_state.rooms
  |> list.find(fn(room) { room.name == room_name })
  |> option.from_result
  |> option.map(fn(room) { room.adjustment })
}

const min_adjustment: Float = -3.0

const max_adjustment: Float = 3.0

fn clamp_adjustment(value: Float) -> Float {
  value
  |> float.max(min_adjustment)
  |> float.min(max_adjustment)
}

/// Simple update function for backward compatibility (no side effects).
/// Used when no dependencies are needed (e.g., simple testing).
pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  update_with_deps(model, msg, no_op_dependencies())
}
