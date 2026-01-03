//// HouseModeActor - singleton actor tracking house-wide mode (Auto/Sleeping).
////
//// Responsibilities:
//// - Track current house mode (Auto/Sleeping)
//// - Accept room actor registrations
//// - Broadcast mode changes to all registered room actors

import deep_heating/actor/room_actor
import deep_heating/mode.{type HouseMode, HouseModeAuto}
import gleam/erlang/process.{type Name, type Subject}
import gleam/list
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
  /// Register a room actor to receive mode change broadcasts
  RegisterRoomActor(room_actor: Subject(room_actor.Message))
}

/// Internal state of the HouseModeActor
type State {
  State(mode: HouseMode, room_actors: List(Subject(room_actor.Message)))
}

/// Start the HouseModeActor without name registration (for testing)
pub fn start_link() -> Result(Subject(Message), actor.StartError) {
  let initial_state = State(mode: HouseModeAuto, room_actors: [])

  actor.new(initial_state)
  |> actor.on_message(handle_message)
  |> actor.start
  |> extract_subject
}

/// Start the HouseModeActor and register it with the given name
pub fn start(
  name: Name(Message),
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  let initial_state = State(mode: HouseModeAuto, room_actors: [])

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
    GetMode(reply_to) -> {
      process.send(reply_to, state.mode)
      actor.continue(state)
    }
    SleepButtonPressed -> {
      let new_mode = mode.HouseModeSleeping
      broadcast_mode_change(state.room_actors, new_mode)
      actor.continue(State(..state, mode: new_mode))
    }
    WakeUp -> {
      let new_mode = mode.HouseModeAuto
      broadcast_mode_change(state.room_actors, new_mode)
      actor.continue(State(..state, mode: new_mode))
    }
    RegisterRoomActor(room_actor) -> {
      actor.continue(
        State(..state, room_actors: [room_actor, ..state.room_actors]),
      )
    }
  }
}

fn broadcast_mode_change(
  room_actors: List(Subject(room_actor.Message)),
  new_mode: HouseMode,
) -> Nil {
  list.each(room_actors, fn(ra) {
    process.send(ra, room_actor.HouseModeChanged(new_mode))
  })
}

fn extract_subject(
  result: Result(actor.Started(Subject(Message)), actor.StartError),
) -> Result(Subject(Message), actor.StartError) {
  case result {
    Ok(started) -> Ok(started.data)
    Error(e) -> Error(e)
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
