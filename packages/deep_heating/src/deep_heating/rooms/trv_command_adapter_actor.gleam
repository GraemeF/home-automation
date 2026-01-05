//// TrvCommandAdapterActor - forwards domain TrvCommand to infrastructure ha_command_actor.
////
//// This actor acts as a bridge between the domain layer (RoomDecisionActor sending
//// TrvCommand) and the infrastructure layer (HaCommandActor sending SetTrvAction).
////
//// Unlike a raw process with receive_forever, this actor:
//// - Is supervisable (can be restarted if it crashes)
//// - Handles OTP system messages (shutdown, tracing)
//// - Can be gracefully stopped
////
//// The actor uses a custom selector to receive TrvCommand messages directly,
//// avoiding the need for a wrapper process.

import deep_heating/home_assistant/ha_command_actor
import deep_heating/rooms/room_decision_actor
import gleam/erlang/process.{type Subject}
import gleam/otp/actor

/// Internal message type - we receive TrvCommand directly
type Message {
  TrvCommand(room_decision_actor.TrvCommand)
}

/// Internal actor state
type State {
  State(ha_commands: Subject(ha_command_actor.Message))
}

/// Start the adapter actor.
/// Returns a Subject(TrvCommand) that can be passed to RoomDecisionActor.
///
/// The actor creates its own Subject for receiving TrvCommand messages and
/// uses a custom selector to handle them, converting them to HA commands.
pub fn start(
  ha_commands: Subject(ha_command_actor.Message),
) -> Result(actor.Started(Subject(room_decision_actor.TrvCommand)), actor.StartError) {
  // Create the Subject in the actor's init, so it's owned by the actor
  actor.new_with_initialiser(5000, fn(_default_subject) {
    // Create a Subject for TrvCommand messages
    let trv_commands: Subject(room_decision_actor.TrvCommand) =
      process.new_subject()
    let initial_state = State(ha_commands: ha_commands)

    // Create a selector that maps TrvCommand -> Message
    let selector =
      process.new_selector()
      |> process.select_map(trv_commands, TrvCommand)

    actor.initialised(initial_state)
    |> actor.selecting(selector)
    |> actor.returning(trv_commands)
    |> Ok
  })
  |> actor.on_message(handle_message)
  |> actor.start
}

fn handle_message(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    TrvCommand(room_decision_actor.TrvCommand(entity_id, mode, target)) -> {
      // Convert domain command to infrastructure command
      process.send(
        state.ha_commands,
        ha_command_actor.SetTrvAction(entity_id, mode, target),
      )
      actor.continue(state)
    }
  }
}
