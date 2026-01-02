//// StateAggregatorActor - collects state snapshots for UI broadcasting.
////
//// This is a stub implementation for setting up the supervision tree.
//// Full implementation will follow in dh-33jq.14.

import deep_heating/state.{type DeepHeatingState}
import gleam/erlang/process.{type Name, type Subject}
import gleam/otp/actor
import gleam/otp/supervision

/// Messages handled by the StateAggregatorActor
pub type Message {
  /// Get the current aggregated state
  GetState(reply_to: Subject(DeepHeatingState))
  /// Subscribe to state updates (for WebSocket clients)
  Subscribe(subscriber: Subject(DeepHeatingState))
}

/// Internal state of the aggregator
pub type State {
  State(current: DeepHeatingState, subscribers: List(Subject(DeepHeatingState)))
}

/// Start the StateAggregatorActor and register it with the given name
pub fn start(
  name: Name(Message),
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  let initial_state =
    State(current: state.empty_deep_heating_state(), subscribers: [])

  actor.new(initial_state)
  |> actor.on_message(handle_message)
  |> actor.start
  |> register_with_name(name)
}

/// Create a child specification for supervision
pub fn child_spec(
  name: Name(Message),
) -> supervision.ChildSpecification(Subject(Message)) {
  supervision.worker(fn() { start(name) })
}

fn handle_message(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    GetState(reply_to) -> {
      process.send(reply_to, state.current)
      actor.continue(state)
    }
    Subscribe(subscriber) -> {
      actor.continue(
        State(..state, subscribers: [subscriber, ..state.subscribers]),
      )
    }
  }
}

fn register_with_name(
  result: Result(actor.Started(Subject(Message)), actor.StartError),
  name: Name(Message),
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  case result {
    Ok(started) -> {
      let _ = process.register(started.pid, name)
      Ok(started)
    }
    Error(e) -> Error(e)
  }
}
