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

import deep_heating/home_assistant/ha_command_actor
import deep_heating/house_mode/house_mode_actor
import deep_heating/state/state_aggregator_actor
import deep_heating/entity_id.{type ClimateEntityId}
import deep_heating/config/home_config.{type HomeConfig, type RoomConfig}
import deep_heating/rooms/room_actor
import deep_heating/rooms/room_adjustments.{type RoomAdjustment}
import deep_heating/rooms/room_decision_actor
import deep_heating/rooms/trv_actor
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Pid, type Subject}
import gleam/list
import gleam/option.{type Option, None, Some}
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
  )
}

/// Create an adapter that forwards domain TrvCommand to infrastructure ha_command_actor.
/// Returns a Subject(TrvCommand) that can be passed to RoomDecisionActor.
///
/// Note: The child process must create its own Subject to receive on it.
/// If the parent creates the Subject, messages go to the parent's mailbox,
/// not the child's - this was a bug that caused message forwarding to fail.
fn create_trv_command_adapter(
  ha_commands: Subject(ha_command_actor.Message),
) -> Subject(room_decision_actor.TrvCommand) {
  // Create a Subject to receive the adapter's Subject back from the spawned process
  let response_subject: Subject(Subject(room_decision_actor.TrvCommand)) =
    process.new_subject()

  // Spawn an unlinked process that creates its own Subject and sends it back
  let _ =
    process.spawn_unlinked(fn() {
      // Create the Subject in THIS process so we can receive on it
      let trv_commands: Subject(room_decision_actor.TrvCommand) =
        process.new_subject()
      // Send the Subject back to the parent
      process.send(response_subject, trv_commands)
      // Now start forwarding
      forward_trv_commands(trv_commands, ha_commands)
    })

  // Wait for the spawned process to send us its Subject
  let assert Ok(trv_commands) = process.receive(response_subject, 5000)
  trv_commands
}

/// Receive TrvCommands and forward to ha_command_actor
fn forward_trv_commands(
  trv_commands: Subject(room_decision_actor.TrvCommand),
  ha_commands: Subject(ha_command_actor.Message),
) -> Nil {
  case process.receive_forever(trv_commands) {
    room_decision_actor.TrvCommand(entity_id, mode, target) -> {
      process.send(
        ha_commands,
        ha_command_actor.SetTrvAction(entity_id, mode, target),
      )
      forward_trv_commands(trv_commands, ha_commands)
    }
  }
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
///
/// Registers the RoomActor with HouseModeActor for mode broadcasts.
pub fn start_room(
  room_config room_config: RoomConfig,
  state_aggregator state_aggregator: Subject(state_aggregator_actor.Message),
  ha_commands ha_commands: Subject(ha_command_actor.Message),
  house_mode house_mode: Subject(house_mode_actor.Message),
  heating_control heating_control: Option(Subject(room_actor.HeatingControlMessage)),
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

  // Create a name for the decision actor
  let decision_actor_name =
    process.new_name("decision_actor_" <> room_config.name)

  // Create an adapter that forwards domain TrvCommand to infrastructure ha_command_actor
  let trv_commands = create_trv_command_adapter(ha_commands)

  // Start the RoomDecisionActor FIRST so we can get its actual Subject
  // (Must start before RoomActor so RoomActor can send to it)
  use decision_started <- result.try(
    room_decision_actor.start_with_trv_commands(trv_commands: trv_commands)
    |> result.map_error(ActorStartError),
  )

  // Get the DecisionActor's actual Subject (created by actor.start internally)
  let decision_subject = decision_started.data

  let decision_ref =
    ActorRef(
      pid: decision_started.pid,
      subject: decision_subject,
      name: decision_actor_name,
    )

  // Coerce the decision subject to the type RoomActor expects
  // (DecisionMessage and room_decision_actor.Message are structurally identical)
  let decision_for_room: Subject(room_actor.DecisionMessage) =
    coerce_subject(decision_subject)

  // Coerce state aggregator subject to type RoomActor expects
  let aggregator_for_room: Subject(room_actor.AggregatorMessage) =
    coerce_subject(state_aggregator)

  // Create a name for the room actor
  let room_actor_name = process.new_name("room_actor_" <> room_config.name)

  // Start the RoomActor with the DecisionActor's actual Subject
  use room_started <- result.try(
    room_actor.start_with_adjustment(
      name: room_config.name,
      schedule: room_schedule,
      decision_actor: decision_for_room,
      state_aggregator: aggregator_for_room,
      heating_control: heating_control,
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

  // Register the room actor with the house mode actor for mode broadcasts
  process.send(house_mode, house_mode_actor.RegisterRoomActor(room_subject))

  // Coerce room subject to type TrvActor expects
  let room_for_trv: Subject(trv_actor.RoomMessage) =
    coerce_subject(room_subject)

  // Start TrvActors under a factory supervisor for fault tolerance
  use trv_refs <- result.try(start_supervised_trv_actors(
    room_config.name,
    room_config.climate_entity_ids,
    room_for_trv,
  ))

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
  trv_actor.start(config.entity_id, config.name, config.room_actor)
}

/// Start TRV actors under a factory supervisor for fault tolerance.
/// Returns the supervisor and actor references.
fn start_supervised_trv_actors(
  room_name: String,
  entity_ids: List(ClimateEntityId),
  room_actor: Subject(trv_actor.RoomMessage),
) -> Result(List(ActorRef(trv_actor.Message)), StartError) {
  // Create names for all TRV actors upfront (names are stable across restarts)
  let configs =
    list.map(entity_ids, fn(entity_id) {
      let entity_id_str = entity_id.climate_entity_id_to_string(entity_id)
      let name =
        process.new_name("trv_actor_" <> room_name <> "_" <> entity_id_str)
      TrvActorConfig(entity_id: entity_id, name: name, room_actor: room_actor)
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

// =============================================================================
// RoomSupervisor Accessors
// =============================================================================

/// Get the room name from a RoomSupervisor
pub fn get_room_name(sup: RoomSupervisor) -> String {
  sup.room_name
}

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
  ha_commands ha_commands: Subject(ha_command_actor.Message),
  house_mode house_mode: Subject(house_mode_actor.Message),
  heating_control heating_control: Option(Subject(room_actor.HeatingControlMessage)),
  initial_adjustments initial_adjustments: List(RoomAdjustment),
) -> Result(RoomsSupervisor, StartError) {
  config.rooms
  |> list.try_map(fn(room_config) {
    start_room(
      room_config: room_config,
      state_aggregator: state_aggregator,
      ha_commands: ha_commands,
      house_mode: house_mode,
      heating_control: heating_control,
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
