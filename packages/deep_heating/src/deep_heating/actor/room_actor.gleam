//// RoomActor - aggregates state for a room.
////
//// Responsibilities:
//// - Aggregate TRV states for the room
//// - Track external temperature sensor reading
//// - Apply house mode and user adjustments
//// - Compute room target temperature
//// - Notify RoomDecisionActor and StateAggregator on changes

import deep_heating/mode.{type HouseMode, HouseModeAuto}
import deep_heating/schedule.{type WeekSchedule}
import deep_heating/temperature.{type Temperature}
import gleam/erlang/process.{type Subject}
import gleam/option.{type Option, None}
import gleam/otp/actor

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
  }
}
