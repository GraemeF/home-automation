//// BoilerCommandAdapterActor - forwards domain BoilerCommand to infrastructure ha_command_actor.
////
//// This actor acts as a bridge between the domain layer (HeatingControlActor sending
//// BoilerCommand) and the infrastructure layer (HaCommandActor sending SetHeatingAction).
////
//// Unlike a raw process with receive_forever, this actor:
//// - Is supervisable (can be restarted if it crashes)
//// - Handles OTP system messages (shutdown, tracing)
//// - Can be gracefully stopped

import deep_heating/heating/heating_control_actor
import deep_heating/home_assistant/ha_command_actor
import gleam/erlang/process.{type Subject}
import gleam/otp/actor

/// Internal message type - we receive BoilerCommand directly
type Message {
  BoilerCommand(heating_control_actor.BoilerCommand)
}

/// Internal actor state
type State {
  State(ha_commands: Subject(ha_command_actor.Message))
}

/// Start the adapter actor.
/// Returns a Subject(BoilerCommand) that can be passed to HeatingControlActor.
///
/// The actor creates its own Subject for receiving BoilerCommand messages and
/// uses a custom selector to handle them, converting them to HA commands.
pub fn start(
  ha_commands: Subject(ha_command_actor.Message),
) -> Result(
  actor.Started(Subject(heating_control_actor.BoilerCommand)),
  actor.StartError,
) {
  actor.new_with_initialiser(5000, fn(_default_subject) {
    // Create a Subject for BoilerCommand messages
    let boiler_commands: Subject(heating_control_actor.BoilerCommand) =
      process.new_subject()
    let initial_state = State(ha_commands: ha_commands)

    // Create a selector that maps BoilerCommand -> Message
    let selector =
      process.new_selector()
      |> process.select_map(boiler_commands, BoilerCommand)

    actor.initialised(initial_state)
    |> actor.selecting(selector)
    |> actor.returning(boiler_commands)
    |> Ok
  })
  |> actor.on_message(handle_message)
  |> actor.start
}

fn handle_message(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    BoilerCommand(heating_control_actor.BoilerCommand(
      entity_id,
      hvac_mode,
      target,
    )) -> {
      // Convert domain command to infrastructure command
      process.send(
        state.ha_commands,
        ha_command_actor.SetHeatingAction(entity_id, hvac_mode, target),
      )
      actor.continue(state)
    }
  }
}
