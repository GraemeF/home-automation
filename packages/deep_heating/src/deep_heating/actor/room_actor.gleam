//// RoomActor - aggregates state for a room.
////
//// Responsibilities:
//// - Aggregate TRV states for the room
//// - Track external temperature sensor reading
//// - Apply house mode and user adjustments
//// - Compute room target temperature
//// - Notify RoomDecisionActor and StateAggregator on changes

import deep_heating/entity_id.{type ClimateEntityId}
import deep_heating/mode.{type HouseMode, HouseModeAuto}
import deep_heating/schedule.{type WeekSchedule}
import deep_heating/temperature.{type Temperature}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/float
import gleam/option.{type Option, None, Some}
import gleam/otp/actor

/// State of a single TRV within the room
pub type TrvState {
  TrvState(
    /// Current temperature reading from the TRV
    temperature: Option(Temperature),
    /// Current target temperature the TRV is set to
    target: Option(Temperature),
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
  let initial_room =
    RoomState(
      name: name,
      temperature: None,
      target_temperature: None,
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
    HouseModeChanged(new_mode) -> {
      let new_room = RoomState(..state.room, house_mode: new_mode)
      let new_state = ActorState(..state, room: new_room)
      notify_state_changed(new_state)
      actor.continue(new_state)
    }
    AdjustmentChanged(adjustment) -> {
      let clamped = clamp_adjustment(adjustment)
      let new_room = RoomState(..state.room, adjustment: clamped)
      let new_state = ActorState(..state, room: new_room)
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
    |> option.unwrap(TrvState(temperature: None, target: None))

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
    |> option.unwrap(TrvState(temperature: None, target: None))

  let updated_trv = TrvState(..current_trv, target: option.Some(target))

  let new_trv_states =
    dict.insert(state.room.trv_states, entity_id, updated_trv)
  let new_room = RoomState(..state.room, trv_states: new_trv_states)
  ActorState(..state, room: new_room)
}

fn notify_state_changed(state: ActorState) -> Nil {
  process.send(state.decision_actor, RoomStateChanged(state.room))
}

const min_adjustment: Float = -3.0

const max_adjustment: Float = 3.0

fn clamp_adjustment(value: Float) -> Float {
  value
  |> float.max(min_adjustment)
  |> float.min(max_adjustment)
}
