//// TrvCommandAdapterActor - forwards domain TrvCommand to infrastructure ha_command_actor.
////
//// This actor acts as a bridge between the domain layer (RoomDecisionActor sending
//// TrvCommand) and the infrastructure layer (HaCommandActor sending SetTrvAction).
////
//// Uses `actor.named()` so it can be found via `named_subject()` after OTP supervisor
//// restarts. The message type is `TrvCommand` directly (not wrapped), which allows
//// standard naming to work.
////
//// The actor looks up HaCommandActor by name on each message, ensuring it always
//// has a fresh reference even after restarts.

import deep_heating/entity_id
import deep_heating/home_assistant/ha_command_actor
import deep_heating/log
import deep_heating/mode
import deep_heating/rooms/room_decision_actor.{type TrvCommand, TrvCommand}
import deep_heating/temperature
import gleam/erlang/process.{type Name, type Subject}
import gleam/otp/actor

/// State - stores HA command actor's name for lookup
type State {
  State(ha_command_name: Name(ha_command_actor.Message))
}

/// Start the adapter actor with a name, looking up HaCommandActor by name.
///
/// - Uses `actor.named()` so the adapter can be found via `named_subject()`
/// - Stores the HA command actor's name, not its Subject
/// - Looks up the HA command actor on each message (survives restarts)
///
/// With RestForOne supervision, if HaCommandActor restarts, this adapter
/// also restarts and gets a fresh name lookup.
pub fn start_named(
  name name: Name(TrvCommand),
  ha_command_name ha_command_name: Name(ha_command_actor.Message),
) -> Result(actor.Started(Subject(TrvCommand)), actor.StartError) {
  actor.new(State(ha_command_name: ha_command_name))
  |> actor.named(name)
  |> actor.on_message(handle_message)
  |> actor.start
}

fn handle_message(
  state: State,
  cmd: TrvCommand,
) -> actor.Next(State, TrvCommand) {
  let TrvCommand(trv_entity_id, hvac_mode, target) = cmd

  log.entity_debug(
    entity_id.climate_entity_id_to_string(trv_entity_id),
    "TRV command: mode="
      <> mode.hvac_mode_to_string(hvac_mode)
      <> ", target="
      <> temperature.format(target),
  )

  // Look up HA command actor by name (fresh reference on each call)
  let ha_subject: Subject(ha_command_actor.Message) =
    process.named_subject(state.ha_command_name)

  // Convert domain command to infrastructure command
  process.send(
    ha_subject,
    ha_command_actor.SetTrvAction(trv_entity_id, hvac_mode, target),
  )

  actor.continue(state)
}
