//// HeatingControlActor - controls the main boiler based on room heating demand.
////
//// Responsibilities:
//// - Receive room state updates from RoomActors
//// - Track which rooms need heating (room temp < target)
//// - Turn boiler ON when any room needs heating
//// - Turn boiler OFF when no rooms need heating
//// - Emit domain BoilerCommand messages (decoupled from HA infrastructure)

import deep_heating/entity_id.{type ClimateEntityId}
import deep_heating/mode.{type HvacMode}
import deep_heating/rooms/room_actor
import deep_heating/temperature.{type Temperature}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Name, type Subject}
import gleam/list
import gleam/option
import gleam/otp/actor
import gleam/otp/supervision

/// Messages handled by the HeatingControlActor
pub type Message {
  /// Get the current heating control state
  GetState(reply_to: Subject(HeatingControlState))
  /// Room state was updated (from RoomActor)
  RoomUpdated(name: String, room_state: room_actor.RoomState)
  /// Boiler status changed (from HaPollerActor)
  BoilerStatusChanged(is_heating: Bool)
}

/// Public view of the heating control state for queries
pub type HeatingControlState {
  HeatingControlState(
    /// Current boiler status
    boiler_is_heating: Bool,
    /// Current room states being tracked
    room_states: Dict(String, room_actor.RoomState),
  )
}

/// Domain command for boiler actions - decoupled from HA infrastructure
pub type BoilerCommand {
  BoilerCommand(entity_id: ClimateEntityId, mode: HvacMode, target: Temperature)
}

/// Internal actor state
type State {
  State(
    boiler_entity_id: ClimateEntityId,
    boiler_commands: Subject(BoilerCommand),
    /// Current boiler status
    boiler_is_heating: Bool,
    /// Track room states to determine heating demand
    room_states: Dict(String, room_actor.RoomState),
  )
}

/// Start the HeatingControlActor with a domain BoilerCommand output subject.
/// This is the preferred way to start the actor - it stays decoupled from HA.
pub fn start(
  boiler_entity_id boiler_entity_id: ClimateEntityId,
  boiler_commands boiler_commands: Subject(BoilerCommand),
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  let initial_state =
    State(
      boiler_entity_id: boiler_entity_id,
      boiler_commands: boiler_commands,
      boiler_is_heating: False,
      room_states: dict.new(),
    )

  actor.new(initial_state)
  |> actor.on_message(handle_message)
  |> actor.start
}

/// Start the HeatingControlActor and register it with the given name
pub fn start_named(
  name: Name(Message),
  boiler_entity_id: ClimateEntityId,
  boiler_commands: Subject(BoilerCommand),
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  let initial_state =
    State(
      boiler_entity_id: boiler_entity_id,
      boiler_commands: boiler_commands,
      boiler_is_heating: False,
      room_states: dict.new(),
    )

  actor.new(initial_state)
  |> actor.named(name)
  |> actor.on_message(handle_message)
  |> actor.start
}

/// Create a child specification for supervision
pub fn child_spec(
  name: Name(Message),
  boiler_entity_id: ClimateEntityId,
  boiler_commands: Subject(BoilerCommand),
) -> supervision.ChildSpecification(Subject(Message)) {
  supervision.worker(fn() {
    start_named(name, boiler_entity_id, boiler_commands)
  })
}

fn handle_message(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    GetState(reply_to) -> {
      let public_state =
        HeatingControlState(
          boiler_is_heating: state.boiler_is_heating,
          room_states: state.room_states,
        )
      process.send(reply_to, public_state)
      actor.continue(state)
    }
    RoomUpdated(name, room_state) -> {
      // Update room state
      let new_room_states = dict.insert(state.room_states, name, room_state)
      let new_state = State(..state, room_states: new_room_states)

      // Recalculate and potentially send command
      let final_state = evaluate_and_send_command(new_state)
      actor.continue(final_state)
    }
    BoilerStatusChanged(is_heating) -> {
      // Just update our knowledge of the boiler's current state
      // This is feedback from HA, not a trigger to change anything
      let new_state = State(..state, boiler_is_heating: is_heating)
      actor.continue(new_state)
    }
  }
}

/// Evaluate heating demand and send command if boiler state needs to change
fn evaluate_and_send_command(state: State) -> State {
  let any_room_needs_heating = does_any_room_need_heating(state.room_states)

  case any_room_needs_heating, state.boiler_is_heating {
    // Room needs heating, boiler is off → turn on
    True, False -> {
      send_boiler_command(state, mode.HvacHeat)
      State(..state, boiler_is_heating: True)
    }
    // No rooms need heating, boiler is on → turn off
    False, True -> {
      send_boiler_command(state, mode.HvacOff)
      State(..state, boiler_is_heating: False)
    }
    // No change needed
    _, _ -> state
  }
}

/// Check if any room needs heating
fn does_any_room_need_heating(
  room_states: Dict(String, room_actor.RoomState),
) -> Bool {
  room_states
  |> dict.values
  |> list.any(room_needs_heating)
}

/// Check if a single room needs heating
fn room_needs_heating(room: room_actor.RoomState) -> Bool {
  case room.temperature, room.target_temperature {
    option.Some(current), option.Some(target) -> {
      // Room needs heating if current temp is below target
      temperature.lt(current, target)
    }
    // If we don't have both temps, assume no heating needed
    _, _ -> False
  }
}

/// Send a domain BoilerCommand
fn send_boiler_command(state: State, hvac_mode: HvacMode) -> Nil {
  let target = boiler_target_for_mode(hvac_mode)
  process.send(
    state.boiler_commands,
    BoilerCommand(state.boiler_entity_id, hvac_mode, target),
  )
}

/// Get the target temperature to send with the boiler command
fn boiler_target_for_mode(hvac_mode: HvacMode) -> Temperature {
  case hvac_mode {
    // When heating, set a high target
    mode.HvacHeat -> temperature.max_trv_command_target
    // When off, set minimum
    _ -> temperature.min_trv_command_target
  }
}
