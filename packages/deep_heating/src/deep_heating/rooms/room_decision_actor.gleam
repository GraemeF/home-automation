//// RoomDecisionActor - decides TRV setpoints based on room state.
////
//// Responsibilities:
//// - Receive room state from RoomActors
//// - Decide what each TRV's target should be
//// - Send TrvCommand (domain commands) to the configured output subject
//// - Implement the "smart" heating logic (compensation)

import deep_heating/entity_id.{type ClimateEntityId}
import deep_heating/mode.{type HvacMode}
import deep_heating/rooms/room_actor
import deep_heating/temperature.{type Temperature}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Name, type Subject}
import gleam/option
import gleam/otp/actor

/// Messages handled by the RoomDecisionActor
pub type Message {
  /// Room state has changed - re-evaluate TRV targets
  RoomStateChanged(room_actor.RoomState)
}

/// Domain command for TRV actions - decoupled from HA infrastructure
pub type TrvCommand {
  TrvCommand(entity_id: ClimateEntityId, mode: HvacMode, target: Temperature)
}

/// Internal actor state
type State {
  State(
    /// Name of the TrvCommandAdapterActor - looked up via named_subject() on each send
    trv_adapter_name: Name(TrvCommand),
    /// Track last sent target per TRV to avoid duplicate commands
    last_sent_targets: Dict(ClimateEntityId, Temperature),
  )
}

/// Start the RoomDecisionActor with a TrvCommandAdapterActor name.
/// The adapter is looked up by name on each command send, making the actor
/// robust to adapter restarts under OTP supervision.
pub fn start_with_trv_adapter_name(
  trv_adapter_name trv_adapter_name: Name(TrvCommand),
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  let initial_state =
    State(trv_adapter_name: trv_adapter_name, last_sent_targets: dict.new())

  actor.new(initial_state)
  |> actor.on_message(handle_message)
  |> actor.start
}

/// Start a named RoomDecisionActor with a TrvCommandAdapterActor name.
/// The actor registers with the given name, allowing it to be addressed
/// via `named_subject(name)` even after restarts under supervision.
/// The adapter is looked up by name on each command send.
pub fn start_named(
  name name: Name(Message),
  trv_adapter_name trv_adapter_name: Name(TrvCommand),
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  let initial_state =
    State(trv_adapter_name: trv_adapter_name, last_sent_targets: dict.new())

  actor.new(initial_state)
  |> actor.named(name)
  |> actor.on_message(handle_message)
  |> actor.start
}

fn handle_message(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    RoomStateChanged(room_state) -> {
      let new_state = evaluate_and_send_commands(state, room_state)
      actor.continue(new_state)
    }
  }
}

fn evaluate_and_send_commands(
  state: State,
  room_state: room_actor.RoomState,
) -> State {
  // For each TRV in the room, compute desired target and send command
  case room_state.target_temperature {
    option.None -> state
    option.Some(room_target) -> {
      dict.fold(
        room_state.trv_states,
        state,
        fn(current_state, entity_id, trv_state) {
          // Skip TRVs that are off - user has explicitly turned them off
          case trv_state.mode {
            mode.HvacOff -> current_state
            _ -> {
              let desired_target =
                compute_desired_trv_target(
                  room_target,
                  room_state.temperature,
                  trv_state.temperature,
                )

              // Only send if target has changed
              let last_target =
                dict.get(current_state.last_sent_targets, entity_id)
              let should_send = case last_target {
                Ok(last) -> !temperature.eq(last, desired_target)
                Error(_) -> True
              }

              case should_send {
                False -> current_state
                True -> {
                  // Target changed or first time, send command
                  // Always set mode to HvacHeat (converts auto→heat)
                  // Look up the TrvCommandAdapterActor by name (survives restarts)
                  let trv_commands: Subject(TrvCommand) =
                    process.named_subject(current_state.trv_adapter_name)
                  process.send(
                    trv_commands,
                    TrvCommand(entity_id, mode.HvacHeat, desired_target),
                  )
                  // Update last sent target
                  State(
                    ..current_state,
                    last_sent_targets: dict.insert(
                      current_state.last_sent_targets,
                      entity_id,
                      desired_target,
                    ),
                  )
                }
              }
            }
          }
        },
      )
    }
  }
}

/// Compute the desired TRV target using offset-based compensation.
/// Formula: trvTarget = round(clamp(roomTarget + trvTemp - roomTemp, 7°C, 32°C))
///
/// This compensates for TRVs that read differently from the external room sensor.
/// If TRV reads higher than room, we set a lower target on the TRV.
/// If TRV reads lower than room, we set a higher target on the TRV.
/// The result is clamped to TRV-safe bounds (7-32°C), then rounded to nearest 0.5°C.
///
/// Rounding direction depends on whether heating is required:
/// - Heating required (room < target): round UP (bias toward more heating)
/// - Heating NOT required (room >= target): round DOWN (prevent overshooting)
fn compute_desired_trv_target(
  room_target: Temperature,
  room_temp: option.Option(Temperature),
  trv_temp: option.Option(Temperature),
) -> Temperature {
  // Determine if heating is required (for rounding direction)
  // If room_temp unknown, assume heating required (conservative - round up)
  let heating_required = case room_temp {
    option.Some(room) -> temperature.lt(room, room_target)
    option.None -> True
  }

  let unclamped = case room_temp, trv_temp {
    // Both temperatures available - use offset formula
    option.Some(room), option.Some(trv) -> {
      let target =
        temperature.unwrap(room_target)
        +. temperature.unwrap(trv)
        -. temperature.unwrap(room)
      temperature.temperature(target)
    }
    // Missing room or TRV temp - fall back to room target
    _, _ -> room_target
  }

  let clamped =
    temperature.clamp(
      unclamped,
      temperature.min_trv_command_target,
      temperature.max_trv_command_target,
    )

  // Round to nearest 0.5°C based on heating requirement
  case heating_required {
    True -> temperature.round_up_half(clamped)
    False -> temperature.round_down_half(clamped)
  }
}
