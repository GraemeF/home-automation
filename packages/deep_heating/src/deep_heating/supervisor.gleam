//// DeepHeatingSupervisor - top-level OTP supervision tree for Deep Heating.
////
//// Supervision tree structure:
//// ```
//// DeepHeatingSupervisor (one_for_one)
//// ├── HouseModeActor
//// ├── StateAggregatorActor
//// ├── HaPollerActor (when started with config)
//// └── RoomsSupervisor (when started with home_config)
//// ```

import deep_heating/event_router_actor
import deep_heating/heating/heating_control_actor
import deep_heating/house_mode/house_mode_actor
import deep_heating/state/state_aggregator_actor
import deep_heating/home_assistant/client.{type HaClient}
import deep_heating/home_assistant/ha_command_actor
import deep_heating/home_assistant/ha_poller_actor
import deep_heating/config/home_config.{type HomeConfig}
import deep_heating/rooms/room_adjustments
import deep_heating/rooms/rooms_supervisor.{type RoomsSupervisor}
import gleam/dict
import gleam/erlang/process.{type Name, type Pid, type Subject}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/static_supervisor as supervisor
import gleam/result

/// Handle to the running supervisor and its children
pub opaque type Supervisor {
  Supervisor(
    pid: Pid,
    house_mode_name: Name(house_mode_actor.Message),
    state_aggregator_name: Name(state_aggregator_actor.Message),
    ha_poller_name: Option(Name(ha_poller_actor.Message)),
    ha_command_name: Option(Name(ha_command_actor.Message)),
  )
}

/// Configuration for starting the supervisor with HaPollerActor
pub type SupervisorConfig {
  SupervisorConfig(
    ha_client: HaClient,
    poller_config: ha_poller_actor.PollerConfig,
    /// Path to persist room adjustments
    adjustments_path: String,
  )
}

/// Configuration for starting the supervisor with HaPollerActor and rooms
pub type SupervisorConfigWithRooms {
  SupervisorConfigWithRooms(
    ha_client: HaClient,
    poller_config: ha_poller_actor.PollerConfig,
    /// Path to persist room adjustments
    adjustments_path: String,
    /// Home configuration defining rooms, TRVs, and schedules
    home_config: HomeConfig,
  )
}

/// Handle to the running supervisor including rooms
pub opaque type SupervisorWithRooms {
  SupervisorWithRooms(
    pid: Pid,
    house_mode_name: Name(house_mode_actor.Message),
    state_aggregator_name: Name(state_aggregator_actor.Message),
    ha_poller_name: Name(ha_poller_actor.Message),
    ha_command_name: Name(ha_command_actor.Message),
    heating_control_name: Name(heating_control_actor.Message),
    rooms_supervisor: RoomsSupervisor,
  )
}

/// Reference to a running actor with its PID
pub type ActorRef(msg) {
  ActorRef(pid: Pid, subject: Subject(msg))
}

/// Start the Deep Heating supervision tree without HaPollerActor.
///
/// Returns a Started record containing the supervisor PID and a handle
/// for querying child actors.
pub fn start() -> Result(actor.Started(Supervisor), actor.StartError) {
  // Create names for our actors so we can look them up later
  let house_mode_name = process.new_name("deep_heating_house_mode")
  let state_aggregator_name = process.new_name("deep_heating_state_aggregator")

  // Build and start the supervision tree
  supervisor.new(supervisor.OneForOne)
  |> supervisor.add(house_mode_actor.child_spec(house_mode_name))
  |> supervisor.add(state_aggregator_actor.child_spec(
    state_aggregator_name,
    room_adjustments.default_path,
  ))
  |> supervisor.start
  |> wrap_result(house_mode_name, state_aggregator_name, None, None)
}

/// Default debounce interval for HA commands in milliseconds
const default_ha_command_debounce_ms = 5000

/// Start the Deep Heating supervision tree with HaPollerActor.
///
/// This variant includes the HaPollerActor for polling Home Assistant.
/// Note: Events are discarded in this mode (no rooms to route to).
pub fn start_with_config(
  config: SupervisorConfig,
) -> Result(actor.Started(Supervisor), actor.StartError) {
  // Create names for our actors so we can look them up later
  let house_mode_name = process.new_name("deep_heating_house_mode")
  let state_aggregator_name = process.new_name("deep_heating_state_aggregator")
  let ha_poller_name = process.new_name("deep_heating_ha_poller")
  let ha_command_name = process.new_name("deep_heating_ha_command")

  // Create an orphaned event spy - events are discarded in this mode
  // (This mode is primarily for testing without full room configuration)
  let event_spy: Subject(ha_poller_actor.PollerEvent) = process.new_subject()

  // Build and start the supervision tree
  supervisor.new(supervisor.OneForOne)
  |> supervisor.add(house_mode_actor.child_spec(house_mode_name))
  |> supervisor.add(state_aggregator_actor.child_spec(
    state_aggregator_name,
    config.adjustments_path,
  ))
  |> supervisor.add(ha_poller_actor.child_spec(
    ha_poller_name,
    config.ha_client,
    config.poller_config,
    event_spy,
  ))
  |> supervisor.add(ha_command_actor.child_spec(
    ha_command_name,
    config.ha_client,
    default_ha_command_debounce_ms,
  ))
  |> supervisor.start
  |> wrap_result(
    house_mode_name,
    state_aggregator_name,
    Some(ha_poller_name),
    Some(ha_command_name),
  )
}

/// Get a reference to the HouseModeActor
pub fn get_house_mode_actor(
  sup: Supervisor,
) -> Result(ActorRef(house_mode_actor.Message), Nil) {
  case process.named(sup.house_mode_name) {
    Ok(pid) -> {
      let subject = process.named_subject(sup.house_mode_name)
      Ok(ActorRef(pid: pid, subject: subject))
    }
    Error(_) -> Error(Nil)
  }
}

/// Get a reference to the StateAggregatorActor
pub fn get_state_aggregator(
  sup: Supervisor,
) -> Result(ActorRef(state_aggregator_actor.Message), Nil) {
  case process.named(sup.state_aggregator_name) {
    Ok(pid) -> {
      let subject = process.named_subject(sup.state_aggregator_name)
      Ok(ActorRef(pid: pid, subject: subject))
    }
    Error(_) -> Error(Nil)
  }
}

/// Get a reference to the HaPollerActor (only available if started with config)
pub fn get_ha_poller(
  sup: Supervisor,
) -> Result(ActorRef(ha_poller_actor.Message), Nil) {
  case sup.ha_poller_name {
    Some(name) -> {
      case process.named(name) {
        Ok(pid) -> {
          let subject = process.named_subject(name)
          Ok(ActorRef(pid: pid, subject: subject))
        }
        Error(_) -> Error(Nil)
      }
    }
    None -> Error(Nil)
  }
}

/// Get a reference to the HaCommandActor (only available if started with config)
pub fn get_ha_command_actor(
  sup: Supervisor,
) -> Result(ActorRef(ha_command_actor.Message), Nil) {
  case sup.ha_command_name {
    Some(name) -> {
      case process.named(name) {
        Ok(pid) -> {
          let subject = process.named_subject(name)
          Ok(ActorRef(pid: pid, subject: subject))
        }
        Error(_) -> Error(Nil)
      }
    }
    None -> Error(Nil)
  }
}

/// Get the supervisor's PID
pub fn pid(sup: Supervisor) -> Pid {
  sup.pid
}

fn wrap_result(
  result: Result(actor.Started(supervisor.Supervisor), actor.StartError),
  house_mode_name: Name(house_mode_actor.Message),
  state_aggregator_name: Name(state_aggregator_actor.Message),
  ha_poller_name: Option(Name(ha_poller_actor.Message)),
  ha_command_name: Option(Name(ha_command_actor.Message)),
) -> Result(actor.Started(Supervisor), actor.StartError) {
  case result {
    Ok(started) -> {
      let sup =
        Supervisor(
          pid: started.pid,
          house_mode_name: house_mode_name,
          state_aggregator_name: state_aggregator_name,
          ha_poller_name: ha_poller_name,
          ha_command_name: ha_command_name,
        )
      Ok(actor.Started(pid: started.pid, data: sup))
    }
    Error(e) -> Error(e)
  }
}

// =============================================================================
// Supervisor with Rooms
// =============================================================================

/// Error type for starting supervisor with rooms
pub type StartWithRoomsError {
  SupervisorStartError(actor.StartError)
  RoomsStartError(rooms_supervisor.StartError)
}

/// Start the Deep Heating supervision tree with HaPollerActor and rooms.
///
/// This variant includes:
/// - HouseModeActor (manages house mode state)
/// - StateAggregatorActor (aggregates room states for UI)
/// - HaCommandActor (sends commands to Home Assistant)
/// - HeatingControlActor (controls boiler based on room heating demand)
/// - RoomsSupervisor (creates per-room actor trees from HomeConfig)
/// - EventRouterActor (routes poller events to appropriate actors)
/// - HaPollerActor (polls Home Assistant for updates)
pub fn start_with_home_config(
  config: SupervisorConfigWithRooms,
) -> Result(actor.Started(SupervisorWithRooms), StartWithRoomsError) {
  // Create names for our actors so we can look them up later
  let house_mode_name = process.new_name("deep_heating_house_mode")
  let state_aggregator_name = process.new_name("deep_heating_state_aggregator")
  let ha_poller_name = process.new_name("deep_heating_ha_poller")
  let ha_command_name = process.new_name("deep_heating_ha_command")
  let heating_control_name = process.new_name("deep_heating_heating_control")

  // Build and start the main supervision tree
  // Note: HeatingControlActor is started manually after supervision
  // to allow proper adapter wiring for domain/infrastructure decoupling
  let supervisor_result =
    supervisor.new(supervisor.OneForOne)
    |> supervisor.add(house_mode_actor.child_spec(house_mode_name))
    |> supervisor.add(state_aggregator_actor.child_spec(
      state_aggregator_name,
      config.adjustments_path,
    ))
    |> supervisor.add(ha_command_actor.child_spec(
      ha_command_name,
      config.ha_client,
      default_ha_command_debounce_ms,
    ))
    |> supervisor.start

  case supervisor_result {
    Error(e) -> Error(SupervisorStartError(e))
    Ok(started) -> {
      // Get the state aggregator subject for room actor registration
      let state_aggregator_subject =
        process.named_subject(state_aggregator_name)

      // Get HaCommandActor subject for TRV commands
      let ha_commands = process.named_subject(ha_command_name)

      // Load initial adjustments from environment
      let initial_adjustments =
        room_adjustments.load_from_env()
        |> result.unwrap([])

      // Get HouseModeActor subject for room registration
      let house_mode_subject = process.named_subject(house_mode_name)

      // Start rooms supervisor with the HomeConfig
      case
        rooms_supervisor.start(
          config: config.home_config,
          state_aggregator: state_aggregator_subject,
          ha_commands: ha_commands,
          house_mode: house_mode_subject,
          initial_adjustments: initial_adjustments,
        )
      {
        Error(e) -> Error(RoomsStartError(e))
        Ok(rooms_sup) -> {
          // Build registries from RoomsSupervisor
          let trv_registry = build_trv_registry(rooms_sup, config.home_config)
          let sensor_registry =
            build_sensor_registry(rooms_sup, config.home_config)

          // Create adapter that converts domain BoilerCommand → ha_command_actor.Message
          let boiler_commands = create_boiler_command_adapter(ha_commands)

          // Start HeatingControlActor with domain-only interface
          case
            heating_control_actor.start_named(
              heating_control_name,
              config.home_config.heating_id,
              boiler_commands,
            )
          {
            Error(e) -> Error(SupervisorStartError(e))
            Ok(heating_started) -> {
              // Start EventRouterActor (reuses house_mode_subject from above)
              let router_config =
                event_router_actor.Config(
                  house_mode_actor: house_mode_subject,
                  trv_registry: trv_registry,
                  sensor_registry: sensor_registry,
                  heating_control_actor: option.Some(heating_started.data),
                )

              case event_router_actor.start(router_config) {
                Error(_) -> {
                  // For now, treat router start failure as a supervisor error
                  Error(SupervisorStartError(actor.InitTimeout))
                }
                Ok(event_router_subject) -> {
                  // Start HaPollerActor with the EventRouter's subject as event_spy
                  case
                    ha_poller_actor.start_named(
                      ha_poller_name,
                      config.ha_client,
                      config.poller_config,
                      event_router_subject,
                    )
                  {
                    Error(e) -> Error(SupervisorStartError(e))
                    Ok(_poller_started) -> {
                      let sup =
                        SupervisorWithRooms(
                          pid: started.pid,
                          house_mode_name: house_mode_name,
                          state_aggregator_name: state_aggregator_name,
                          ha_poller_name: ha_poller_name,
                          ha_command_name: ha_command_name,
                          heating_control_name: heating_control_name,
                          rooms_supervisor: rooms_sup,
                        )
                      Ok(actor.Started(pid: started.pid, data: sup))
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

/// Build a TrvActorRegistry from the RoomsSupervisor's TrvActors
fn build_trv_registry(
  rooms_sup: RoomsSupervisor,
  home_config: HomeConfig,
) -> event_router_actor.TrvActorRegistry {
  // For each room, pair entity_ids with TrvActor subjects
  let pairs =
    rooms_supervisor.get_room_supervisors(rooms_sup)
    |> list.flat_map(fn(room_sup) {
      // Get room name directly from RoomSupervisor for reliable matching
      let room_name = rooms_supervisor.get_room_name(room_sup)

      // Find the RoomConfig by name
      let room_config_opt =
        list.find(home_config.rooms, fn(rc) { rc.name == room_name })

      case room_config_opt {
        Ok(room_config) -> {
          let trv_actors = rooms_supervisor.get_trv_actors(room_sup)
          // Zip entity_ids with TrvActor subjects
          list.zip(room_config.climate_entity_ids, trv_actors)
          |> list.map(fn(pair) {
            let #(entity_id, trv_ref) = pair
            #(entity_id, trv_ref.subject)
          })
        }
        Error(_) -> []
      }
    })

  event_router_actor.build_trv_registry(dict.from_list(pairs))
}

fn build_sensor_registry(
  rooms_sup: RoomsSupervisor,
  home_config: HomeConfig,
) -> event_router_actor.SensorRegistry {
  // For each room with a temperature sensor, map sensor_id to RoomActor subject
  let pairs =
    home_config.rooms
    |> list.filter_map(fn(room_config) {
      // Only include rooms that have a temperature sensor
      case room_config.temperature_sensor_entity_id {
        option.None -> Error(Nil)
        option.Some(sensor_id) -> {
          // Find the RoomSupervisor for this room by name
          case rooms_supervisor.get_room_by_name(rooms_sup, room_config.name) {
            Error(_) -> Error(Nil)
            Ok(room_sup) -> {
              case rooms_supervisor.get_room_actor(room_sup) {
                Error(_) -> Error(Nil)
                Ok(room_ref) -> Ok(#(sensor_id, room_ref.subject))
              }
            }
          }
        }
      }
    })

  event_router_actor.build_sensor_registry(dict.from_list(pairs))
}

/// Get the rooms supervisor
pub fn get_rooms_supervisor(
  sup: SupervisorWithRooms,
) -> Result(RoomsSupervisor, Nil) {
  Ok(sup.rooms_supervisor)
}

/// Get a reference to the HeatingControlActor (only available with home config)
pub fn get_heating_control_actor(
  sup: SupervisorWithRooms,
) -> Result(ActorRef(heating_control_actor.Message), Nil) {
  case process.named(sup.heating_control_name) {
    Ok(pid) -> {
      let subject = process.named_subject(sup.heating_control_name)
      Ok(ActorRef(pid: pid, subject: subject))
    }
    Error(_) -> Error(Nil)
  }
}

// =============================================================================
// Domain Command Adapters
// =============================================================================

/// Create an adapter that forwards domain BoilerCommand to infrastructure ha_command_actor.
/// Returns a Subject(BoilerCommand) that can be passed to HeatingControlActor.
fn create_boiler_command_adapter(
  ha_commands: Subject(ha_command_actor.Message),
) -> Subject(heating_control_actor.BoilerCommand) {
  let boiler_commands: Subject(heating_control_actor.BoilerCommand) =
    process.new_subject()

  // Spawn an unlinked process that forwards BoilerCommand → ha_command_actor.Message
  let _ =
    process.spawn_unlinked(fn() {
      forward_boiler_commands(boiler_commands, ha_commands)
    })

  boiler_commands
}

/// Receive BoilerCommands and forward to ha_command_actor
fn forward_boiler_commands(
  boiler_commands: Subject(heating_control_actor.BoilerCommand),
  ha_commands: Subject(ha_command_actor.Message),
) -> Nil {
  case process.receive_forever(boiler_commands) {
    heating_control_actor.BoilerCommand(entity_id, mode, target) -> {
      process.send(
        ha_commands,
        ha_command_actor.SetHeatingAction(entity_id, mode, target),
      )
      forward_boiler_commands(boiler_commands, ha_commands)
    }
  }
}
