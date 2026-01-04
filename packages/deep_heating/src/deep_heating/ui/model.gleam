import deep_heating/state.{type DeepHeatingState}
import gleam/option.{type Option, None}
import lustre/effect.{type Effect}

/// The UI model containing connection status and application state.
pub type Model {
  Model(connected: Bool, state: Option(DeepHeatingState))
}

/// Create the initial model for the Lustre application.
pub fn init(_flags: Nil) -> #(Model, Effect(msg)) {
  #(Model(connected: False, state: None), effect.none())
}
