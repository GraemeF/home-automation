//// EventRouterActor - routes HaPollerActor events to appropriate actors.
////
//// Responsibilities:
//// - Listen for PollerEvents and route them to appropriate actors
//// - Route TrvUpdated events to correct TrvActor (by entity_id → subject lookup)
//// - Route SleepButtonPressed events to HouseModeActor
//// - Ignore poll status events (PollCompleted, PollFailed, etc.)

import deep_heating/actor/ha_poller_actor.{type PollerEvent}
import deep_heating/actor/house_mode_actor
import deep_heating/actor/trv_actor
import deep_heating/entity_id.{type ClimateEntityId}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor

/// Opaque type for entity_id → TrvActor Subject mapping
pub opaque type TrvActorRegistry {
  TrvActorRegistry(mapping: Dict(ClimateEntityId, Subject(trv_actor.Message)))
}

/// Build a TrvActorRegistry from a Dict of entity_ids to TrvActor Subjects
pub fn build_trv_registry(
  mapping: Dict(ClimateEntityId, Subject(trv_actor.Message)),
) -> TrvActorRegistry {
  TrvActorRegistry(mapping)
}

/// Configuration for starting the EventRouterActor
pub type Config {
  Config(
    house_mode_actor: Subject(house_mode_actor.Message),
    trv_registry: TrvActorRegistry,
  )
}

/// Internal actor state
type State {
  State(
    house_mode_actor: Subject(house_mode_actor.Message),
    trv_registry: TrvActorRegistry,
  )
}

/// Start the EventRouterActor.
/// Returns the subject that the router listens on - callers should send
/// PollerEvents to this subject for routing.
pub fn start(config: Config) -> Result(Subject(PollerEvent), actor.StartError) {
  let initial_state =
    State(
      house_mode_actor: config.house_mode_actor,
      trv_registry: config.trv_registry,
    )

  actor.new(initial_state)
  |> actor.on_message(handle_message)
  |> actor.start
  |> extract_subject
}

fn handle_message(
  state: State,
  message: PollerEvent,
) -> actor.Next(State, PollerEvent) {
  route_event(message, state)
  actor.continue(state)
}

fn route_event(event: PollerEvent, state: State) -> Nil {
  case event {
    ha_poller_actor.TrvUpdated(entity_id, update) -> {
      route_trv_update(entity_id, update, state.trv_registry)
    }
    ha_poller_actor.SleepButtonPressed -> {
      process.send(state.house_mode_actor, house_mode_actor.SleepButtonPressed)
    }
    // Ignore poll status events
    ha_poller_actor.PollingStarted -> Nil
    ha_poller_actor.PollingStopped -> Nil
    ha_poller_actor.PollCompleted -> Nil
    ha_poller_actor.PollFailed(_) -> Nil
    ha_poller_actor.BackoffApplied(_) -> Nil
    ha_poller_actor.BackoffReset -> Nil
  }
}

fn route_trv_update(
  entity_id: ClimateEntityId,
  update: trv_actor.TrvUpdate,
  trv_registry: TrvActorRegistry,
) -> Nil {
  // Look up the TrvActor subject directly
  case dict.get(trv_registry.mapping, entity_id) {
    Ok(trv_subject) -> {
      process.send(trv_subject, trv_actor.Update(update))
    }
    Error(_) -> {
      // Unknown entity_id - ignore
      Nil
    }
  }
}

fn extract_subject(
  result: Result(actor.Started(Subject(PollerEvent)), actor.StartError),
) -> Result(Subject(PollerEvent), actor.StartError) {
  case result {
    Ok(started) -> Ok(started.data)
    Error(e) -> Error(e)
  }
}
