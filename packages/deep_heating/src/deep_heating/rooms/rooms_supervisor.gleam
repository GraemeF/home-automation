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

import deep_heating/config/home_config.{type HomeConfig, type RoomConfig}
import deep_heating/entity_id.{type ClimateEntityId}
import deep_heating/home_assistant/ha_command_actor
import deep_heating/house_mode/house_mode_actor
import deep_heating/rooms/room_actor
import deep_heating/rooms/room_adjustments.{type RoomAdjustment}
import deep_heating/rooms/room_decision_actor
import deep_heating/rooms/trv_actor
import deep_heating/rooms/trv_command_adapter_actor
import deep_heating/state/state_aggregator_actor
import deep_heating/timer.{type SendAfter}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Name, type Pid, type Subject}
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

/// Coerce a Name from one message type to another.
/// This is safe when the underlying message representations are compatible.
@external(erlang, "rooms_supervisor_ffi", "identity")
fn coerce_name(name: Name(a)) -> Name(b)

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
    room_actor_name: process.Name(trv_actor.RoomMessage),
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
///
/// Registers the RoomActor with HouseModeActor for mode broadcasts.
pub fn start_room(
  room_config room_config: RoomConfig,
  state_aggregator state_aggregator: Subject(state_aggregator_actor.Message),
  ha_command_name ha_command_name: process.Name(ha_command_actor.Message),
  house_mode house_mode: Subject(house_mode_actor.Message),
  heating_control heating_control: Option(
    Subject(room_actor.HeatingControlMessage),
  ),
  initial_adjustments initial_adjustments: List(RoomAdjustment),
  room_send_after room_send_after: SendAfter(room_actor.Message),
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

  // Create names for actors
  let decision_actor_name =
    process.new_name("decision_actor_" <> room_config.name)
  let trv_adapter_name = process.new_name("trv_adapter_" <> room_config.name)

  // Start the TRV command adapter actor - uses named pattern for OTP supervision
  use _adapter_started <- result.try(
    trv_command_adapter_actor.start_named(
      name: trv_adapter_name,
      ha_command_name: ha_command_name,
    )
    |> result.map_error(ActorStartError),
  )

  // Start the RoomDecisionActor - looks up TrvCommandAdapterActor by name
  // Uses start_named for OTP supervision support
  use decision_started <- result.try(
    room_decision_actor.start_named(
      name: decision_actor_name,
      trv_adapter_name: trv_adapter_name,
    )
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

  // Coerce the decision actor name to the type RoomActor expects
  // (DecisionMessage and room_decision_actor.Message are structurally identical)
  let decision_name_for_room: Name(room_actor.DecisionMessage) =
    coerce_name(decision_actor_name)

  // Coerce state aggregator subject to type RoomActor expects
  let aggregator_for_room: Subject(room_actor.AggregatorMessage) =
    coerce_subject(state_aggregator)

  // Create a name for the room actor
  let room_actor_name = process.new_name("room_actor_" <> room_config.name)

  // Start the RoomActor - looks up RoomDecisionActor by name
  // Uses start_named_with_options for OTP supervision support and testable timers
  use room_started <- result.try(
    room_actor.start_named_with_options(
      actor_name: room_actor_name,
      room_name: room_config.name,
      schedule: room_schedule,
      decision_actor_name: decision_name_for_room,
      state_aggregator: aggregator_for_room,
      heating_control: heating_control,
      get_time: room_actor.get_current_datetime,
      timer_interval_ms: room_actor.default_timer_interval_ms,
      initial_adjustment: initial_adjustment,
      send_after: room_send_after,
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

  // Coerce room actor name to type TrvActor expects
  // (RoomMessage and trv_actor.RoomMessage are structurally identical)
  let room_name_for_trv: process.Name(trv_actor.RoomMessage) =
    coerce_name(room_actor_name)

  // Start TrvActors under a factory supervisor for fault tolerance
  use trv_refs <- result.try(start_supervised_trv_actors(
    room_config.name,
    room_config.climate_entity_ids,
    room_name_for_trv,
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
  trv_actor.start(config.entity_id, config.name, config.room_actor_name)
}

/// Start TRV actors under a factory supervisor for fault tolerance.
/// Returns the supervisor and actor references.
fn start_supervised_trv_actors(
  room_name: String,
  entity_ids: List(ClimateEntityId),
  room_actor_name: process.Name(trv_actor.RoomMessage),
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
        room_actor_name: room_actor_name,
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
/// Rooms without schedules are skipped (sensor-only rooms don't need actors).
pub fn start(
  config config: HomeConfig,
  state_aggregator state_aggregator: Subject(state_aggregator_actor.Message),
  ha_command_name ha_command_name: process.Name(ha_command_actor.Message),
  house_mode house_mode: Subject(house_mode_actor.Message),
  heating_control heating_control: Option(
    Subject(room_actor.HeatingControlMessage),
  ),
  initial_adjustments initial_adjustments: List(RoomAdjustment),
  room_send_after room_send_after: SendAfter(room_actor.Message),
) -> Result(RoomsSupervisor, StartError) {
  // Only start actors for rooms with schedules (controllable rooms)
  // Sensor-only rooms (no schedule) are skipped
  config.rooms
  |> list.filter(fn(room_config) { option.is_some(room_config.schedule) })
  |> list.try_map(fn(room_config) {
    start_room(
      room_config: room_config,
      state_aggregator: state_aggregator,
      ha_command_name: ha_command_name,
      house_mode: house_mode,
      heating_control: heating_control,
      initial_adjustments: initial_adjustments,
      room_send_after: room_send_after,
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
