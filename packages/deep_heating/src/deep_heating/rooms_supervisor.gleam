//// RoomsSupervisor - starts per-room actor supervision trees from configuration.
////
//// Creates a supervision tree for each room:
//// ```
//// RoomsSupervisor
//// ├── RoomSupervisor(lounge)
//// │   ├── RoomActor(lounge)
//// │   ├── TrvActor(lounge_trv)
//// │   └── RoomDecisionActor(lounge)
//// ├── RoomSupervisor(bedroom)
//// │   ├── RoomActor(bedroom)
//// │   ├── TrvActor(bedroom_trv_1)
//// │   ├── TrvActor(bedroom_trv_2)
//// │   └── RoomDecisionActor(bedroom)
//// └── ...
//// ```

import deep_heating/actor/room_actor
import deep_heating/actor/room_decision_actor
import deep_heating/actor/state_aggregator_actor
import deep_heating/actor/trv_actor
import deep_heating/entity_id.{type ClimateEntityId}
import deep_heating/home_config.{type HomeConfig, type RoomConfig}
import deep_heating/room_adjustments.{type RoomAdjustment}
import deep_heating/temperature.{type Temperature}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Pid, type Subject}
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/otp/factory_supervisor as factory
import gleam/result

// =============================================================================
// FFI for Subject type coercion
// =============================================================================

/// Coerce a Subject from one message type to another.
/// This is safe when the underlying message representations are compatible.
@external(erlang, "rooms_supervisor_ffi", "identity")
fn coerce_subject(subject: Subject(a)) -> Subject(b)

// =============================================================================
// Types
// =============================================================================

/// Reference to a running actor with its registered name
pub type ActorRef(msg) {
  ActorRef(pid: Pid, subject: Subject(msg), name: process.Name(msg))
}

/// Handle to a single room's supervision tree
pub opaque type RoomSupervisor {
  RoomSupervisor(
    room_name: String,
    room_actor: ActorRef(room_actor.Message),
    trv_actors: List(ActorRef(trv_actor.Message)),
    decision_actor: ActorRef(room_decision_actor.Message),
  )
}

/// Handle to all room supervision trees
pub opaque type RoomsSupervisor {
  RoomsSupervisor(rooms: Dict(String, RoomSupervisor))
}

/// Errors that can occur when starting room supervisors
pub type StartError {
  ActorStartError(actor.StartError)
  ConfigError(String)
}

/// Configuration for starting a TRV actor under supervision
type TrvActorConfig {
  TrvActorConfig(
    entity_id: ClimateEntityId,
    name: process.Name(trv_actor.Message),
    room_actor: Subject(trv_actor.RoomMessage),
    ha_commands: Subject(trv_actor.HaCommand),
  )
}

// =============================================================================
// RoomSupervisor - Single Room
// =============================================================================

/// Start actors for a single room.
///
/// Creates and wires together:
/// - RoomActor (aggregates TRV states)
/// - TrvActors (one per TRV in the room)
/// - RoomDecisionActor (computes TRV setpoints)
pub fn start_room(
  room_config room_config: RoomConfig,
  state_aggregator state_aggregator: Subject(state_aggregator_actor.Message),
  ha_commands ha_commands: Subject(trv_actor.HaCommand),
  initial_adjustments initial_adjustments: List(RoomAdjustment),
) -> Result(RoomSupervisor, StartError) {
  // Get schedule - rooms must have a schedule configured
  use room_schedule <- result.try(case room_config.schedule {
    Some(s) -> Ok(s)
    None ->
      Error(ConfigError(
        "Room '" <> room_config.name <> "' has no schedule configured",
      ))
  })

  // Look up initial adjustment for this room
  let initial_adjustment =
    room_adjustments.get_adjustment(initial_adjustments, room_config.name)

  // First, create a subject for decision actor messages.
  // We'll use this when starting the room actor, then start the decision actor.
  let decision_subject: Subject(room_decision_actor.Message) =
    process.new_subject()

  // Coerce the decision subject to the type RoomActor expects
  let decision_for_room: Subject(room_actor.DecisionMessage) =
    coerce_subject(decision_subject)

  // Coerce state aggregator subject to type RoomActor expects
  let aggregator_for_room: Subject(room_actor.AggregatorMessage) =
    coerce_subject(state_aggregator)

  // Create a name for the room actor
  let room_actor_name = process.new_name("room_actor_" <> room_config.name)

  // Start the RoomActor with initial adjustment
  use room_started <- result.try(
    room_actor.start_with_adjustment(
      name: room_config.name,
      schedule: room_schedule,
      decision_actor: decision_for_room,
      state_aggregator: aggregator_for_room,
      initial_adjustment: initial_adjustment,
    )
    |> result.map_error(ActorStartError),
  )

  let room_subject = room_started.data
  let room_ref =
    ActorRef(
      pid: room_started.pid,
      subject: room_subject,
      name: room_actor_name,
    )

  // Register the room actor with the state aggregator for adjustment forwarding
  process.send(
    state_aggregator,
    state_aggregator_actor.RegisterRoomActor(room_config.name, room_subject),
  )

  // Coerce room subject to type TrvActor expects
  let room_for_trv: Subject(trv_actor.RoomMessage) =
    coerce_subject(room_subject)

  // Start TrvActors under a factory supervisor for fault tolerance
  use trv_refs <- result.try(start_supervised_trv_actors(
    room_config.name,
    room_config.climate_entity_ids,
    room_for_trv,
    ha_commands,
  ))

  // Start the command forwarder actor - it creates its own Subject
  use trv_command_subject <- result.try(start_trv_command_forwarder(trv_refs))

  // Create a name for the decision actor
  let decision_actor_name =
    process.new_name("decision_actor_" <> room_config.name)

  // Start the RoomDecisionActor with the forwarder's Subject
  use decision_started <- result.try(
    room_decision_actor.start(trv_commands: trv_command_subject)
    |> result.map_error(ActorStartError),
  )

  let decision_ref =
    ActorRef(
      pid: decision_started.pid,
      subject: decision_started.data,
      name: decision_actor_name,
    )

  Ok(RoomSupervisor(
    room_name: room_config.name,
    room_actor: room_ref,
    trv_actors: trv_refs,
    decision_actor: decision_ref,
  ))
}

/// Start a TRV actor from configuration - used by factory_supervisor
fn start_trv_from_config(
  config: TrvActorConfig,
) -> Result(actor.Started(Subject(trv_actor.Message)), actor.StartError) {
  trv_actor.start(
    config.entity_id,
    config.name,
    config.room_actor,
    config.ha_commands,
  )
}

/// Start TRV actors under a factory supervisor for fault tolerance.
/// Returns the supervisor and actor references.
fn start_supervised_trv_actors(
  room_name: String,
  entity_ids: List(ClimateEntityId),
  room_actor: Subject(trv_actor.RoomMessage),
  ha_commands: Subject(trv_actor.HaCommand),
) -> Result(List(ActorRef(trv_actor.Message)), StartError) {
  // Create names for all TRV actors upfront (names are stable across restarts)
  let configs =
    list.map(entity_ids, fn(entity_id) {
      let entity_id_str = entity_id.climate_entity_id_to_string(entity_id)
      let name =
        process.new_name("trv_actor_" <> room_name <> "_" <> entity_id_str)
      TrvActorConfig(
        entity_id: entity_id,
        name: name,
        room_actor: room_actor,
        ha_commands: ha_commands,
      )
    })

  // Start factory supervisor for TRV actors
  use trv_supervisor <- result.try(
    factory.worker_child(start_trv_from_config)
    |> factory.start
    |> result.map_error(ActorStartError),
  )

  // Start each TRV actor under the supervisor
  list.try_map(configs, fn(config) {
    factory.start_child(trv_supervisor.data, config)
    |> result.map(fn(started) {
      ActorRef(pid: started.pid, subject: started.data, name: config.name)
    })
    |> result.map_error(ActorStartError)
  })
}

/// Internal state for the TrvCommand forwarder actor
type ForwarderState {
  ForwarderState(trv_subjects: List(Subject(trv_actor.Message)))
}

/// Start an actor that forwards TrvCommands to the appropriate TrvActor.
/// Returns the Subject that RoomDecisionActor should send commands to.
fn start_trv_command_forwarder(
  trv_refs: List(ActorRef(trv_actor.Message)),
) -> Result(Subject(room_decision_actor.TrvCommand), StartError) {
  let trv_subjects = list.map(trv_refs, fn(ref) { ref.subject })
  let initial_state = ForwarderState(trv_subjects: trv_subjects)

  actor.new(initial_state)
  |> actor.on_message(handle_forwarder_message)
  |> actor.start
  |> result.map(fn(started) { started.data })
  |> result.map_error(ActorStartError)
}

fn handle_forwarder_message(
  state: ForwarderState,
  message: room_decision_actor.TrvCommand,
) -> actor.Next(ForwarderState, room_decision_actor.TrvCommand) {
  case message {
    room_decision_actor.SetTrvTarget(entity_id, _mode, target) -> {
      // Forward to the matching TRV actor
      forward_set_target(state.trv_subjects, entity_id, target)
      actor.continue(state)
    }
  }
}

fn forward_set_target(
  trv_subjects: List(Subject(trv_actor.Message)),
  target_entity_id: ClimateEntityId,
  target: Temperature,
) -> Nil {
  list.each(trv_subjects, fn(trv_subject) {
    // Query TRV state to check entity ID
    let reply = process.new_subject()
    process.send(trv_subject, trv_actor.GetState(reply))
    case process.receive(reply, 100) {
      Ok(state) if state.entity_id == target_entity_id -> {
        process.send(trv_subject, trv_actor.SetTarget(target))
      }
      _ -> Nil
    }
  })
}

// =============================================================================
// RoomSupervisor Accessors
// =============================================================================

/// Get the RoomActor reference from a RoomSupervisor
pub fn get_room_actor(
  sup: RoomSupervisor,
) -> Result(ActorRef(room_actor.Message), Nil) {
  Ok(sup.room_actor)
}

/// Get all TrvActor references from a RoomSupervisor
pub fn get_trv_actors(sup: RoomSupervisor) -> List(ActorRef(trv_actor.Message)) {
  sup.trv_actors
}

/// Get the RoomDecisionActor reference from a RoomSupervisor
pub fn get_decision_actor(
  sup: RoomSupervisor,
) -> Result(ActorRef(room_decision_actor.Message), Nil) {
  Ok(sup.decision_actor)
}

// =============================================================================
// RoomsSupervisor - Multiple Rooms
// =============================================================================

/// Start room supervision trees for all rooms in the configuration.
pub fn start(
  config config: HomeConfig,
  state_aggregator state_aggregator: Subject(state_aggregator_actor.Message),
  ha_commands ha_commands: Subject(trv_actor.HaCommand),
  initial_adjustments initial_adjustments: List(RoomAdjustment),
) -> Result(RoomsSupervisor, StartError) {
  config.rooms
  |> list.try_map(fn(room_config) {
    start_room(
      room_config: room_config,
      state_aggregator: state_aggregator,
      ha_commands: ha_commands,
      initial_adjustments: initial_adjustments,
    )
    |> result.map(fn(room_sup) { #(room_config.name, room_sup) })
  })
  |> result.map(fn(pairs) { RoomsSupervisor(rooms: dict.from_list(pairs)) })
}

/// Get all room supervisors
pub fn get_room_supervisors(sup: RoomsSupervisor) -> List(RoomSupervisor) {
  dict.values(sup.rooms)
}

/// Get a room supervisor by name
pub fn get_room_by_name(
  sup: RoomsSupervisor,
  name: String,
) -> Result(RoomSupervisor, Nil) {
  dict.get(sup.rooms, name)
}
