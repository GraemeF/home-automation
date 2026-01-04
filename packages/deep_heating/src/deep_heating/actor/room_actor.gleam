//// RoomActor - aggregates state for a room.
////
//// Responsibilities:
//// - Aggregate TRV states for the room
//// - Track external temperature sensor reading
//// - Apply house mode and user adjustments
//// - Compute room target temperature
//// - Notify RoomDecisionActor and StateAggregator on changes

import deep_heating/entity_id.{type ClimateEntityId}
import deep_heating/mode.{
  type HouseMode, type HvacMode, HouseModeAuto, HouseModeSleeping, HvacOff,
}
import deep_heating/schedule.{type TimeOfDay, type WeekSchedule, type Weekday}
import deep_heating/temperature.{type Temperature}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/float
import gleam/option.{type Option, None, Some}
import gleam/otp/actor

// =============================================================================
// Erlang FFI for getting current time and weekday
// =============================================================================

/// Get current local time from Erlang calendar
@external(erlang, "calendar", "local_time")
fn erlang_local_time() -> #(#(Int, Int, Int), #(Int, Int, Int))

/// Get day of week (1=Monday, 7=Sunday) from Erlang calendar
@external(erlang, "calendar", "day_of_the_week")
fn erlang_day_of_the_week(year: Int, month: Int, day: Int) -> Int

/// Convert Erlang day-of-week int (1=Monday, 7=Sunday) to Weekday
fn int_to_weekday(day_int: Int) -> Weekday {
  case day_int {
    1 -> schedule.Monday
    2 -> schedule.Tuesday
    3 -> schedule.Wednesday
    4 -> schedule.Thursday
    5 -> schedule.Friday
    6 -> schedule.Saturday
    _ -> schedule.Sunday
  }
}

/// Get current time and weekday from system
fn get_current_datetime() -> #(Weekday, TimeOfDay) {
  let #(#(year, month, day), #(hour, minute, _second)) = erlang_local_time()
  let weekday = int_to_weekday(erlang_day_of_the_week(year, month, day))
  let assert Ok(time) = schedule.time_of_day(hour, minute)
  #(weekday, time)
}

/// State of a single TRV within the room
pub type TrvState {
  TrvState(
    /// Current temperature reading from the TRV
    temperature: Option(Temperature),
    /// Current target temperature the TRV is set to
    target: Option(Temperature),
    /// Current HVAC mode of the TRV
    mode: HvacMode,
    /// Whether the TRV is currently heating
    is_heating: Bool,
  )
}

/// State visible to external observers
pub type RoomState {
  RoomState(
    /// Room name
    name: String,
    /// Current temperature from external sensor
    temperature: Option(Temperature),
    /// Computed target temperature for the room
    target_temperature: Option(Temperature),
    /// House-wide operating mode
    house_mode: HouseMode,
    /// User adjustment to scheduled temperature (degrees)
    adjustment: Float,
    /// State of each TRV in this room
    trv_states: Dict(ClimateEntityId, TrvState),
  )
}

/// Messages that RoomActor notifies to the decision actor
pub type DecisionMessage {
  RoomStateChanged(RoomState)
}

/// Messages that RoomActor notifies to the state aggregator
pub type AggregatorMessage {
  RoomUpdated(name: String, state: RoomState)
}

/// Messages handled by the RoomActor
pub type Message {
  /// Get the current room state
  GetState(reply_to: Subject(RoomState))
  /// TRV temperature reading changed (from TrvActor)
  TrvTemperatureChanged(entity_id: ClimateEntityId, temperature: Temperature)
  /// TRV target temperature changed (from TrvActor)
  TrvTargetChanged(entity_id: ClimateEntityId, target: Temperature)
  /// TRV HVAC mode changed (from TrvActor)
  TrvModeChanged(entity_id: ClimateEntityId, mode: HvacMode)
  /// TRV is_heating status changed (from TrvActor)
  TrvIsHeatingChanged(entity_id: ClimateEntityId, is_heating: Bool)
  /// House-wide mode changed (from HouseModeActor)
  HouseModeChanged(mode: HouseMode)
  /// User adjustment changed (from WebSocket client)
  AdjustmentChanged(adjustment: Float)
  /// External temperature sensor reading changed (from HaPollerActor)
  ExternalTempChanged(temperature: Temperature)
}

/// Internal actor state including dependencies
type ActorState {
  ActorState(
    room: RoomState,
    schedule: WeekSchedule,
    decision_actor: Subject(DecisionMessage),
    state_aggregator: Subject(AggregatorMessage),
  )
}

/// Start the RoomActor with the given configuration
pub fn start(
  name name: String,
  schedule schedule: WeekSchedule,
  decision_actor decision_actor: Subject(DecisionMessage),
  state_aggregator state_aggregator: Subject(AggregatorMessage),
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  // Compute initial target temperature based on schedule and current time
  let #(weekday, time) = get_current_datetime()
  let initial_target =
    compute_target_temperature(
      schedule: schedule,
      house_mode: HouseModeAuto,
      adjustment: 0.0,
      day: weekday,
      time: time,
    )

  let initial_room =
    RoomState(
      name: name,
      temperature: None,
      target_temperature: initial_target,
      house_mode: HouseModeAuto,
      adjustment: 0.0,
      trv_states: dict.new(),
    )
  let initial_state =
    ActorState(
      room: initial_room,
      schedule: schedule,
      decision_actor: decision_actor,
      state_aggregator: state_aggregator,
    )

  actor.new(initial_state)
  |> actor.on_message(handle_message)
  |> actor.start
}

fn handle_message(
  state: ActorState,
  message: Message,
) -> actor.Next(ActorState, Message) {
  case message {
    GetState(reply_to) -> {
      process.send(reply_to, state.room)
      actor.continue(state)
    }
    TrvTemperatureChanged(entity_id, temperature) -> {
      let new_state = update_trv_temperature(state, entity_id, temperature)
      notify_state_changed(new_state)
      actor.continue(new_state)
    }
    TrvTargetChanged(entity_id, target) -> {
      let new_state = update_trv_target(state, entity_id, target)
      notify_state_changed(new_state)
      actor.continue(new_state)
    }
    TrvModeChanged(entity_id, trv_mode) -> {
      let new_state = update_trv_mode(state, entity_id, trv_mode)
      notify_state_changed(new_state)
      actor.continue(new_state)
    }
    TrvIsHeatingChanged(entity_id, is_heating) -> {
      let new_state = update_trv_is_heating(state, entity_id, is_heating)
      notify_state_changed(new_state)
      actor.continue(new_state)
    }
    HouseModeChanged(new_mode) -> {
      let new_room = RoomState(..state.room, house_mode: new_mode)
      let updated_state = ActorState(..state, room: new_room)
      // Recompute target temperature with new house mode
      let new_state = recompute_room_target(updated_state)
      notify_state_changed(new_state)
      actor.continue(new_state)
    }
    AdjustmentChanged(adjustment) -> {
      let clamped = clamp_adjustment(adjustment)
      let new_room = RoomState(..state.room, adjustment: clamped)
      let updated_state = ActorState(..state, room: new_room)
      // Recompute target temperature with new adjustment
      let new_state = recompute_room_target(updated_state)
      notify_state_changed(new_state)
      actor.continue(new_state)
    }
    ExternalTempChanged(temperature) -> {
      let new_room = RoomState(..state.room, temperature: Some(temperature))
      let new_state = ActorState(..state, room: new_room)
      notify_state_changed(new_state)
      actor.continue(new_state)
    }
  }
}

fn update_trv_temperature(
  state: ActorState,
  entity_id: ClimateEntityId,
  temperature: Temperature,
) -> ActorState {
  let current_trv =
    dict.get(state.room.trv_states, entity_id)
    |> option.from_result
    |> option.unwrap(TrvState(
      temperature: None,
      target: None,
      mode: HvacOff,
      is_heating: False,
    ))

  let updated_trv =
    TrvState(..current_trv, temperature: option.Some(temperature))

  let new_trv_states =
    dict.insert(state.room.trv_states, entity_id, updated_trv)
  let new_room = RoomState(..state.room, trv_states: new_trv_states)
  ActorState(..state, room: new_room)
}

fn update_trv_target(
  state: ActorState,
  entity_id: ClimateEntityId,
  target: Temperature,
) -> ActorState {
  let current_trv =
    dict.get(state.room.trv_states, entity_id)
    |> option.from_result
    |> option.unwrap(TrvState(
      temperature: None,
      target: None,
      mode: HvacOff,
      is_heating: False,
    ))

  let updated_trv = TrvState(..current_trv, target: option.Some(target))

  let new_trv_states =
    dict.insert(state.room.trv_states, entity_id, updated_trv)
  let new_room = RoomState(..state.room, trv_states: new_trv_states)
  ActorState(..state, room: new_room)
}

fn update_trv_mode(
  state: ActorState,
  entity_id: ClimateEntityId,
  trv_mode: HvacMode,
) -> ActorState {
  let current_trv =
    dict.get(state.room.trv_states, entity_id)
    |> option.from_result
    |> option.unwrap(TrvState(
      temperature: None,
      target: None,
      mode: HvacOff,
      is_heating: False,
    ))

  let updated_trv = TrvState(..current_trv, mode: trv_mode)

  let new_trv_states =
    dict.insert(state.room.trv_states, entity_id, updated_trv)
  let new_room = RoomState(..state.room, trv_states: new_trv_states)
  ActorState(..state, room: new_room)
}

fn update_trv_is_heating(
  state: ActorState,
  entity_id: ClimateEntityId,
  is_heating: Bool,
) -> ActorState {
  let current_trv =
    dict.get(state.room.trv_states, entity_id)
    |> option.from_result
    |> option.unwrap(TrvState(
      temperature: None,
      target: None,
      mode: HvacOff,
      is_heating: False,
    ))

  let updated_trv = TrvState(..current_trv, is_heating: is_heating)

  let new_trv_states =
    dict.insert(state.room.trv_states, entity_id, updated_trv)
  let new_room = RoomState(..state.room, trv_states: new_trv_states)
  ActorState(..state, room: new_room)
}

fn notify_state_changed(state: ActorState) -> Nil {
  process.send(state.decision_actor, RoomStateChanged(state.room))
  process.send(state.state_aggregator, RoomUpdated(state.room.name, state.room))
}

/// Recompute the target temperature for the room based on current state and time
fn recompute_room_target(state: ActorState) -> ActorState {
  let #(weekday, time) = get_current_datetime()
  let new_target =
    compute_target_temperature(
      schedule: state.schedule,
      house_mode: state.room.house_mode,
      adjustment: state.room.adjustment,
      day: weekday,
      time: time,
    )
  let new_room = RoomState(..state.room, target_temperature: new_target)
  ActorState(..state, room: new_room)
}

/// Compute the target temperature based on schedule, house mode, and adjustment.
/// This is a pure function that can be tested independently of the actor.
///
/// - In Auto mode: scheduled temp + adjustment, clamped to [min_room_target, max_trv_command_target]
/// - In Sleeping mode: returns min_room_target (16°C)
pub fn compute_target_temperature(
  schedule schedule: WeekSchedule,
  house_mode house_mode: HouseMode,
  adjustment adjustment: Float,
  day day: Weekday,
  time time: TimeOfDay,
) -> Option(Temperature) {
  case house_mode {
    HouseModeSleeping -> Some(temperature.min_room_target)
    HouseModeAuto -> {
      let scheduled = schedule.get_scheduled_temperature(schedule, day, time)
      let adjusted =
        temperature.add(scheduled, temperature.temperature(adjustment))
      let clamped =
        temperature.clamp(
          adjusted,
          temperature.min_room_target,
          temperature.max_trv_command_target,
        )
      Some(clamped)
    }
  }
}

const min_adjustment: Float = -3.0

const max_adjustment: Float = 3.0

fn clamp_adjustment(value: Float) -> Float {
  value
  |> float.max(min_adjustment)
  |> float.min(max_adjustment)
}
