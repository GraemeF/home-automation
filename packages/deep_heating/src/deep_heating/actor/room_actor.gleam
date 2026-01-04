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
  type HouseMode, type HvacMode, type RoomMode, HouseModeAuto, HouseModeSleeping,
  HvacOff, RoomModeOff,
}
import deep_heating/schedule.{type TimeOfDay, type WeekSchedule, type Weekday}
import deep_heating/state
import deep_heating/temperature.{type Temperature}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/float
import gleam/list
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
    /// Derived room mode (Off if any TRV is off, otherwise from house_mode)
    room_mode: RoomMode,
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
  RoomUpdated(name: String, state: state.RoomState)
}

/// Function type for getting current date/time (for testability)
pub type GetDateTime =
  fn() -> #(Weekday, TimeOfDay)

/// Default timer interval in milliseconds (60 seconds)
pub const default_timer_interval_ms: Int = 60_000

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
  /// Internal: timer fired, recompute target from schedule
  ReComputeTarget
}

/// Internal actor state including dependencies
type ActorState {
  ActorState(
    room: RoomState,
    schedule: WeekSchedule,
    decision_actor: Subject(DecisionMessage),
    state_aggregator: Subject(AggregatorMessage),
    /// Function to get current date/time
    get_time: GetDateTime,
    /// Timer interval in milliseconds (0 to disable)
    timer_interval_ms: Int,
    /// Self subject for scheduling timer messages
    self_subject: Option(Subject(Message)),
  )
}

/// Start the RoomActor with the given configuration.
/// Uses the default 60-second timer interval for schedule refresh and zero adjustment.
pub fn start(
  name name: String,
  schedule schedule: WeekSchedule,
  decision_actor decision_actor: Subject(DecisionMessage),
  state_aggregator state_aggregator: Subject(AggregatorMessage),
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  start_with_adjustment(
    name: name,
    schedule: schedule,
    decision_actor: decision_actor,
    state_aggregator: state_aggregator,
    initial_adjustment: 0.0,
  )
}

/// Start the RoomActor with an initial adjustment value.
/// Uses the default 60-second timer interval for schedule refresh.
pub fn start_with_adjustment(
  name name: String,
  schedule schedule: WeekSchedule,
  decision_actor decision_actor: Subject(DecisionMessage),
  state_aggregator state_aggregator: Subject(AggregatorMessage),
  initial_adjustment initial_adjustment: Float,
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  start_with_timer_interval(
    name: name,
    schedule: schedule,
    decision_actor: decision_actor,
    state_aggregator: state_aggregator,
    get_time: get_current_datetime,
    timer_interval_ms: default_timer_interval_ms,
    initial_adjustment: initial_adjustment,
  )
}

/// Start the RoomActor with custom time provider and timer interval.
/// Timer interval is in milliseconds (use 0 to disable timer).
pub fn start_with_timer_interval(
  name name: String,
  schedule schedule: WeekSchedule,
  decision_actor decision_actor: Subject(DecisionMessage),
  state_aggregator state_aggregator: Subject(AggregatorMessage),
  get_time get_time: GetDateTime,
  timer_interval_ms timer_interval_ms: Int,
  initial_adjustment initial_adjustment: Float,
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  // Clamp initial adjustment to valid range
  let clamped_adjustment = clamp_adjustment(initial_adjustment)

  // Compute initial target temperature based on schedule and current time
  let #(weekday, time) = get_time()
  let initial_target =
    compute_target_temperature(
      schedule: schedule,
      house_mode: HouseModeAuto,
      adjustment: clamped_adjustment,
      day: weekday,
      time: time,
    )

  let initial_trv_states = dict.new()
  let initial_room =
    RoomState(
      name: name,
      temperature: None,
      target_temperature: initial_target,
      house_mode: HouseModeAuto,
      room_mode: derive_room_mode(initial_trv_states, HouseModeAuto),
      adjustment: clamped_adjustment,
      trv_states: initial_trv_states,
    )

  actor.new_with_initialiser(1000, fn(self_subject) {
    // Schedule initial timer if interval > 0
    case timer_interval_ms > 0 {
      True -> {
        process.send_after(self_subject, timer_interval_ms, ReComputeTarget)
        Nil
      }
      False -> Nil
    }

    let initial_state =
      ActorState(
        room: initial_room,
        schedule: schedule,
        decision_actor: decision_actor,
        state_aggregator: state_aggregator,
        get_time: get_time,
        timer_interval_ms: timer_interval_ms,
        self_subject: Some(self_subject),
      )

    actor.initialised(initial_state)
    |> actor.returning(self_subject)
    |> Ok
  })
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
      let new_room_mode = derive_room_mode(state.room.trv_states, new_mode)
      let new_room =
        RoomState(..state.room, house_mode: new_mode, room_mode: new_room_mode)
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
    ReComputeTarget -> {
      // Timer fired - recompute target temperature from schedule
      let new_state = recompute_room_target(state)
      notify_state_changed(new_state)
      // Reschedule the timer for the next evaluation
      reschedule_timer(new_state)
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
  let new_room_mode = derive_room_mode(new_trv_states, state.room.house_mode)
  let new_room =
    RoomState(
      ..state.room,
      trv_states: new_trv_states,
      room_mode: new_room_mode,
    )
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
  let new_room_mode = derive_room_mode(new_trv_states, state.room.house_mode)
  let new_room =
    RoomState(
      ..state.room,
      trv_states: new_trv_states,
      room_mode: new_room_mode,
    )
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
  let new_room_mode = derive_room_mode(new_trv_states, state.room.house_mode)
  let new_room =
    RoomState(
      ..state.room,
      trv_states: new_trv_states,
      room_mode: new_room_mode,
    )
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
  let new_room_mode = derive_room_mode(new_trv_states, state.room.house_mode)
  let new_room =
    RoomState(
      ..state.room,
      trv_states: new_trv_states,
      room_mode: new_room_mode,
    )
  ActorState(..state, room: new_room)
}

fn notify_state_changed(actor_state: ActorState) -> Nil {
  process.send(actor_state.decision_actor, RoomStateChanged(actor_state.room))
  // Convert internal RoomState to state.RoomState for the aggregator
  let aggregator_state = to_aggregator_state(actor_state.room)
  process.send(
    actor_state.state_aggregator,
    RoomUpdated(actor_state.room.name, aggregator_state),
  )
}

/// Convert internal RoomState to state.RoomState for the aggregator
fn to_aggregator_state(room: RoomState) -> state.RoomState {
  // Convert TRV states to RadiatorState list
  let radiators =
    dict.to_list(room.trv_states)
    |> list.map(fn(pair) {
      let #(entity_id, trv) = pair
      state.RadiatorState(
        name: entity_id.climate_entity_id_to_string(entity_id),
        temperature: option.map(trv.temperature, fn(t) {
          state.TemperatureReading(temperature: t, time: 0)
        }),
        target_temperature: option.map(trv.target, fn(t) {
          state.TemperatureReading(temperature: t, time: 0)
        }),
        desired_target_temperature: None,
        is_heating: Some(trv.is_heating),
      )
    })

  // Check if any TRV is heating
  let is_any_heating =
    dict.values(room.trv_states)
    |> list.any(fn(trv) { trv.is_heating })

  state.RoomState(
    name: room.name,
    temperature: option.map(room.temperature, fn(t) {
      state.TemperatureReading(temperature: t, time: 0)
    }),
    target_temperature: room.target_temperature,
    radiators: radiators,
    mode: Some(room.room_mode),
    is_heating: Some(is_any_heating),
    adjustment: room.adjustment,
  )
}

/// Recompute the target temperature for the room based on current state and time
fn recompute_room_target(state: ActorState) -> ActorState {
  let #(weekday, time) = { state.get_time }()
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

/// Reschedule the timer for the next evaluation cycle
fn reschedule_timer(state: ActorState) -> Nil {
  case state.self_subject, state.timer_interval_ms > 0 {
    Some(self), True -> {
      process.send_after(self, state.timer_interval_ms, ReComputeTarget)
      Nil
    }
    _, _ -> Nil
  }
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

/// Derive the room mode from TRV modes and house mode.
/// If any TRV is in HvacOff mode, room mode is RoomModeOff.
/// Otherwise, derive from house mode.
pub fn derive_room_mode(
  trv_states: Dict(ClimateEntityId, TrvState),
  house_mode: HouseMode,
) -> RoomMode {
  let any_trv_off =
    dict.values(trv_states)
    |> list.any(fn(trv) { trv.mode == HvacOff })

  case any_trv_off {
    True -> RoomModeOff
    False -> mode.house_mode_to_room_mode(house_mode)
  }
}
