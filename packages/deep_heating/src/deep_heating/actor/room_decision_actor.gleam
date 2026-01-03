//// RoomDecisionActor - decides TRV setpoints based on room state.
////
//// Responsibilities:
//// - Receive room state from RoomActors
//// - Decide what each TRV's target should be
//// - Send SetTarget commands to TrvActors
//// - Implement the "smart" heating logic (compensation)

import deep_heating/actor/room_actor
import deep_heating/entity_id.{type ClimateEntityId}
import deep_heating/temperature.{type Temperature}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/option
import gleam/otp/actor

/// Commands sent to TRV actors
pub type TrvCommand {
  SetTrvTarget(entity_id: ClimateEntityId, target: Temperature)
}

/// Messages handled by the RoomDecisionActor
pub type Message {
  /// Room state has changed - re-evaluate TRV targets
  RoomStateChanged(room_actor.RoomState)
}

/// Internal actor state
type State {
  State(
    trv_commands: Subject(TrvCommand),
    /// Track last sent target per TRV to avoid duplicate commands
    last_sent_targets: Dict(ClimateEntityId, Temperature),
  )
}

/// Start the RoomDecisionActor
pub fn start(
  trv_commands trv_commands: Subject(TrvCommand),
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  let initial_state =
    State(trv_commands: trv_commands, last_sent_targets: dict.new())

  actor.new(initial_state)
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
        fn(current_state, entity_id, _trv_state) {
          let desired_target =
            compute_desired_trv_target(room_target, room_state.temperature)

          // Only send if target has changed
          let last_target = dict.get(current_state.last_sent_targets, entity_id)
          let should_send = case last_target {
            Ok(last) -> !temperature.eq(last, desired_target)
            Error(_) -> True
          }

          case should_send {
            False -> current_state
            True -> {
              // Target changed or first time, send command
              process.send(
                current_state.trv_commands,
                SetTrvTarget(entity_id, desired_target),
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
        },
      )
    }
  }
}

/// Compute the desired TRV target based on room temperature.
/// If room is cold (>0.5°C below target), push TRV higher to compensate.
/// If room is hot (>0.5°C above target), back off TRV.
fn compute_desired_trv_target(
  room_target: Temperature,
  room_temp: option.Option(Temperature),
) -> Temperature {
  case room_temp {
    option.None -> room_target
    option.Some(actual) -> {
      let diff = temperature.unwrap(room_target) -. temperature.unwrap(actual)
      case diff {
        d if d >. 0.5 ->
          // Room is cold, push TRV higher
          temperature.temperature(temperature.unwrap(room_target) +. 2.0)
        d if d <. -0.5 ->
          // Room is hot, back off TRV
          temperature.temperature(temperature.unwrap(room_target) -. 1.0)
        _ ->
          // Room at target
          room_target
      }
    }
  }
}
