//// HeatingControlAdapterActor - forwards room updates to HeatingControlActor.
////
//// This actor acts as a bridge between the domain layer (RoomActors sending
//// HeatingControlMessage) and the HeatingControlActor.
////
//// Unlike a raw process with receive_forever, this actor:
//// - Is supervisable (can be restarted if it crashes)
//// - Handles OTP system messages (shutdown, tracing)
//// - Can be gracefully stopped

import deep_heating/heating/heating_control_actor
import deep_heating/rooms/room_actor
import gleam/erlang/process.{type Subject}
import gleam/otp/actor

/// Internal message type - we receive HeatingControlMessage directly
type Message {
  HeatingControlMessage(room_actor.HeatingControlMessage)
}

/// Internal actor state
type State {
  State(heating_control: Subject(heating_control_actor.Message))
}

/// Start the adapter actor.
/// Returns a Subject(HeatingControlMessage) that can be passed to RoomActors.
///
/// The actor creates its own Subject for receiving HeatingControlMessage and
/// uses a custom selector to handle them, converting them to HeatingControlActor messages.
pub fn start(
  heating_control: Subject(heating_control_actor.Message),
) -> Result(
  actor.Started(Subject(room_actor.HeatingControlMessage)),
  actor.StartError,
) {
  actor.new_with_initialiser(5000, fn(_default_subject) {
    // Create a Subject for HeatingControlMessage
    let room_updates: Subject(room_actor.HeatingControlMessage) =
      process.new_subject()
    let initial_state = State(heating_control: heating_control)

    // Create a selector that maps HeatingControlMessage -> Message
    let selector =
      process.new_selector()
      |> process.select_map(room_updates, HeatingControlMessage)

    actor.initialised(initial_state)
    |> actor.selecting(selector)
    |> actor.returning(room_updates)
    |> Ok
  })
  |> actor.on_message(handle_message)
  |> actor.start
}

fn handle_message(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    HeatingControlMessage(room_actor.HeatingRoomUpdated(name, room_state)) -> {
      // Forward room update to HeatingControlActor
      process.send(
        state.heating_control,
        heating_control_actor.RoomUpdated(name, room_state),
      )
      actor.continue(state)
    }
  }
}
