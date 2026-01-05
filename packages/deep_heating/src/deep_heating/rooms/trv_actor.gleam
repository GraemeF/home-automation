//// TrvActor - holds state for a single TRV (Thermostatic Radiator Valve).
////
//// Responsibilities:
//// - Store current TRV state (temperature, target, mode, isHeating)
//// - Receive updates from HaPollerActor
//// - Notify parent RoomActor when state changes
//// - Forward SetTarget/SetMode commands to HaCommandActor

import deep_heating/entity_id.{type ClimateEntityId}
import deep_heating/mode.{type HvacMode, HvacOff}
import deep_heating/temperature.{type Temperature}
import gleam/erlang/process.{type Name, type Subject}
import gleam/option.{type Option, None}
import gleam/otp/actor

/// State of the TRV actor
pub type TrvState {
  TrvState(
    entity_id: ClimateEntityId,
    temperature: Option(Temperature),
    target: Option(Temperature),
    mode: HvacMode,
    is_heating: Bool,
  )
}

/// Update from Home Assistant containing new TRV readings
pub type TrvUpdate {
  TrvUpdate(
    temperature: Option(Temperature),
    target: Option(Temperature),
    mode: HvacMode,
    is_heating: Bool,
  )
}

/// Messages handled by the TrvActor
pub type Message {
  /// Get the current TRV state
  GetState(reply_to: Subject(TrvState))
  /// Update from Home Assistant poller
  Update(TrvUpdate)
}

/// Messages that can be sent to a RoomActor
pub type RoomMessage {
  /// TRV temperature reading changed
  TrvTemperatureChanged(entity_id: ClimateEntityId, temperature: Temperature)
  /// TRV target temperature changed
  TrvTargetChanged(entity_id: ClimateEntityId, target: Temperature)
  /// TRV HVAC mode changed
  TrvModeChanged(entity_id: ClimateEntityId, mode: HvacMode)
  /// TRV is_heating status changed
  TrvIsHeatingChanged(entity_id: ClimateEntityId, is_heating: Bool)
}

/// Internal actor state including dependencies
type ActorState {
  ActorState(trv: TrvState, room_actor_name: Name(RoomMessage))
}

/// Start the TrvActor with the given entity ID, name, and dependencies.
/// The actor registers with the given name, allowing it to be addressed
/// via `named_subject(name)` even after restarts.
///
/// The room_actor_name is stored and looked up dynamically when sending messages,
/// allowing the TrvActor to survive RoomActor restarts under supervision.
pub fn start(
  entity_id: ClimateEntityId,
  name: Name(Message),
  room_actor_name: Name(RoomMessage),
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  let initial_trv =
    TrvState(
      entity_id: entity_id,
      temperature: None,
      target: None,
      mode: HvacOff,
      is_heating: False,
    )
  let initial_state =
    ActorState(trv: initial_trv, room_actor_name: room_actor_name)

  actor.new(initial_state)
  |> actor.named(name)
  |> actor.on_message(handle_message)
  |> actor.start
}

/// Send a message to the RoomActor by looking up its name.
/// The name lookup creates a Subject that references the registered name,
/// allowing the TrvActor to survive RoomActor restarts under supervision.
fn send_to_room(name: Name(RoomMessage), msg: RoomMessage) -> Nil {
  let room_actor: Subject(RoomMessage) = process.named_subject(name)
  process.send(room_actor, msg)
}

fn handle_message(
  state: ActorState,
  message: Message,
) -> actor.Next(ActorState, Message) {
  case message {
    GetState(reply_to) -> {
      process.send(reply_to, state.trv)
      actor.continue(state)
    }
    Update(update) -> {
      let old_trv = state.trv
      let new_trv =
        TrvState(
          ..old_trv,
          temperature: update.temperature,
          target: update.target,
          mode: update.mode,
          is_heating: update.is_heating,
        )

      // Notify room actor of temperature changes
      notify_temperature_change(
        state.room_actor_name,
        old_trv.entity_id,
        old_trv.temperature,
        new_trv.temperature,
      )

      // Notify room actor of target changes
      notify_target_change(
        state.room_actor_name,
        old_trv.entity_id,
        old_trv.target,
        new_trv.target,
      )

      // Notify room actor of mode changes
      notify_mode_change(
        state.room_actor_name,
        old_trv.entity_id,
        old_trv.mode,
        new_trv.mode,
      )

      // Notify room actor of is_heating changes
      notify_is_heating_change(
        state.room_actor_name,
        old_trv.entity_id,
        old_trv.is_heating,
        new_trv.is_heating,
      )

      actor.continue(ActorState(..state, trv: new_trv))
    }
  }
}

fn notify_temperature_change(
  room_actor_name: Name(RoomMessage),
  entity_id: ClimateEntityId,
  old_temp: Option(Temperature),
  new_temp: Option(Temperature),
) -> Nil {
  case old_temp, new_temp {
    // Temperature changed to a new value
    _, option.Some(temp) if old_temp != new_temp -> {
      send_to_room(room_actor_name, TrvTemperatureChanged(entity_id, temp))
    }
    _, _ -> Nil
  }
}

fn notify_target_change(
  room_actor_name: Name(RoomMessage),
  entity_id: ClimateEntityId,
  old_target: Option(Temperature),
  new_target: Option(Temperature),
) -> Nil {
  case old_target, new_target {
    // Target changed to a new value
    _, option.Some(target) if old_target != new_target -> {
      send_to_room(room_actor_name, TrvTargetChanged(entity_id, target))
    }
    _, _ -> Nil
  }
}

fn notify_mode_change(
  room_actor_name: Name(RoomMessage),
  entity_id: ClimateEntityId,
  old_mode: HvacMode,
  new_mode: HvacMode,
) -> Nil {
  case old_mode != new_mode {
    True -> send_to_room(room_actor_name, TrvModeChanged(entity_id, new_mode))
    False -> Nil
  }
}

fn notify_is_heating_change(
  room_actor_name: Name(RoomMessage),
  entity_id: ClimateEntityId,
  old_is_heating: Bool,
  new_is_heating: Bool,
) -> Nil {
  case old_is_heating != new_is_heating {
    True ->
      send_to_room(
        room_actor_name,
        TrvIsHeatingChanged(entity_id, new_is_heating),
      )
    False -> Nil
  }
}
