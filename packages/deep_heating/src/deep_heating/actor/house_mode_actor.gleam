//// HouseModeActor - singleton actor tracking house-wide mode (Auto/Sleeping).
////
//// This is a stub implementation for setting up the supervision tree.
//// Full implementation will follow in dh-33jq.13.

import deep_heating/mode.{type HouseMode, HouseModeAuto}
import gleam/erlang/process.{type Name, type Subject}
import gleam/otp/actor
import gleam/otp/supervision

/// Messages handled by the HouseModeActor
pub type Message {
  /// Get the current house mode
  GetMode(reply_to: Subject(HouseMode))
  /// Set the house to sleeping mode (goodnight button pressed)
  SleepButtonPressed
  /// Wake up the house (timer or manual)
  WakeUp
}

/// Start the HouseModeActor and register it with the given name
pub fn start(
  name: Name(Message),
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  actor.new(HouseModeAuto)
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

fn handle_message(
  state: HouseMode,
  message: Message,
) -> actor.Next(HouseMode, Message) {
  case message {
    GetMode(reply_to) -> {
      process.send(reply_to, state)
      actor.continue(state)
    }
    SleepButtonPressed -> {
      actor.continue(mode.HouseModeSleeping)
    }
    WakeUp -> {
      actor.continue(mode.HouseModeAuto)
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
