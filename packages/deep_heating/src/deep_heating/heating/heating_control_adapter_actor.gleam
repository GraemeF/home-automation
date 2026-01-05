//// HeatingControlAdapterActor - forwards room updates to HeatingControlActor.
////
//// This actor acts as a bridge between the domain layer (RoomActors sending
//// HeatingControlMessage) and the HeatingControlActor.
////
//// Uses `actor.named()` so it can be found via `named_subject()` after OTP supervisor
//// restarts. The message type is `HeatingControlMessage` directly (not wrapped), which
//// allows standard naming to work.
////
//// The actor looks up HeatingControlActor by name on each message, ensuring it always
//// has a fresh reference even after restarts.

import deep_heating/heating/heating_control_actor
import deep_heating/rooms/room_actor.{
  type HeatingControlMessage, HeatingRoomUpdated,
}
import gleam/erlang/process.{type Name, type Subject}
import gleam/otp/actor

/// State - stores HeatingControlActor's name for lookup
type State {
  State(heating_control_name: Name(heating_control_actor.Message))
}

/// Start the adapter actor with a name, looking up HeatingControlActor by name.
///
/// - Uses `actor.named()` so the adapter can be found via `named_subject()`
/// - Stores the HeatingControlActor's name, not its Subject
/// - Looks up the HeatingControlActor on each message (survives restarts)
///
/// With RestForOne supervision, if HeatingControlActor restarts, this adapter
/// also restarts and gets a fresh name lookup.
pub fn start_named(
  name name: Name(HeatingControlMessage),
  heating_control_name heating_control_name: Name(heating_control_actor.Message),
) -> Result(actor.Started(Subject(HeatingControlMessage)), actor.StartError) {
  actor.new(State(heating_control_name: heating_control_name))
  |> actor.named(name)
  |> actor.on_message(handle_message)
  |> actor.start
}

fn handle_message(
  state: State,
  msg: HeatingControlMessage,
) -> actor.Next(State, HeatingControlMessage) {
  case msg {
    HeatingRoomUpdated(name, room_state) -> {
      // Look up HeatingControlActor by name (fresh reference on each call)
      let heating_subject: Subject(heating_control_actor.Message) =
        process.named_subject(state.heating_control_name)

      // Forward room update to HeatingControlActor
      process.send(
        heating_subject,
        heating_control_actor.RoomUpdated(name, room_state),
      )

      actor.continue(state)
    }
  }
}
