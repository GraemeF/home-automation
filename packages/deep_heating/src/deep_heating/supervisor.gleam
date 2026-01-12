//// DeepHeatingSupervisor - top-level OTP supervision tree for Deep Heating.
////
//// Supervision tree structure:
//// ```
//// DeepHeatingSupervisor (one_for_one)
//// ├── StateAggregatorActor (OTP supervised)
//// ├── HouseModeActor
//// ├── HaCommandActor
//// ├── HeatingControlActor
//// ├── HaPollerActor
//// └── RoomsSupervisor (per-room actor trees)
//// ```

import deep_heating/config/home_config.{type HomeConfig}
import deep_heating/event_router_actor
import deep_heating/heating/boiler_command_adapter_actor
import deep_heating/heating/heating_control_actor
import deep_heating/heating/heating_control_adapter_actor
import deep_heating/home_assistant/client.{type HaClient}
import deep_heating/home_assistant/ha_command_actor
import deep_heating/home_assistant/ha_poller_actor
import deep_heating/home_assistant/logging_command_actor
import deep_heating/house_mode/house_mode_actor
import deep_heating/log
import deep_heating/mode
import deep_heating/rooms/room_actor
import deep_heating/rooms/room_adjustments
import deep_heating/rooms/rooms_supervisor.{type RoomsSupervisor}
import deep_heating/state/state_aggregator_actor
import deep_heating/timer
import gleam/dict
import gleam/erlang/process.{type Name, type Pid, type Subject}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/static_supervisor as supervisor
import gleam/result

// =============================================================================
// Actor Dependencies - injectable for testing
// =============================================================================

/// Dependencies for HouseModeActor
pub type HouseModeDeps {
  HouseModeDeps(send_after: timer.SendAfter(house_mode_actor.Message))
}

/// Dependencies for RoomActor
pub type RoomActorDeps {
  RoomActorDeps(send_after: timer.SendAfter(room_actor.Message))
}

/// Dependencies for HaCommandActor
pub type HaCommandDeps {
  HaCommandDeps(
    send_after: timer.SendAfter(ha_command_actor.Message),
    /// Debounce delay for HA commands in milliseconds.
    /// Use 0 to disable debouncing (commands fire immediately).
    debounce_ms: Int,
  )
}

/// Dependencies for StateAggregatorActor
pub type StateAggregatorDeps {
  StateAggregatorDeps(
    send_after: timer.SendAfter(state_aggregator_actor.Message),
    /// Throttle period for broadcasts in milliseconds.
    /// Use 0 to disable throttling (broadcasts happen immediately).
    throttle_ms: Int,
  )
}

/// Dependencies for HaPollerActor
pub type HaPollerDeps {
  HaPollerDeps(send_after: timer.SendAfter(ha_poller_actor.Message))
}

/// Configuration for starting the supervisor
pub type Config {
  Config(
    ha_client: HaClient,
    poller_config: ha_poller_actor.PollerConfig,
    /// Path to persist room adjustments
    adjustments_path: String,
    /// Home configuration defining rooms, TRVs, and schedules
    home_config: HomeConfig,
    /// Optional prefix for actor names (for test isolation)
    name_prefix: Option(String),
    /// Optional time provider for testing (defaults to real time)
    time_provider: Option(house_mode_actor.TimeProvider),
    /// Dry-run mode: log commands instead of sending to Home Assistant
    dry_run: Bool,
    /// Actor dependencies - use default_*_deps() for production, inject spy_send_after for tests
    house_mode_deps: HouseModeDeps,
    room_actor_deps: RoomActorDeps,
    ha_command_deps: HaCommandDeps,
    state_aggregator_deps: StateAggregatorDeps,
    ha_poller_deps: HaPollerDeps,
  )
}

/// Default production dependencies using real timers
pub fn default_house_mode_deps() -> HouseModeDeps {
  HouseModeDeps(send_after: timer.real_send_after)
}

pub fn default_room_actor_deps() -> RoomActorDeps {
  RoomActorDeps(send_after: timer.real_send_after)
}

pub fn default_ha_command_deps() -> HaCommandDeps {
  HaCommandDeps(
    send_after: timer.real_send_after,
    debounce_ms: default_ha_command_debounce_ms,
  )
}

pub fn default_state_aggregator_deps() -> StateAggregatorDeps {
  StateAggregatorDeps(
    send_after: timer.real_send_after,
    throttle_ms: state_aggregator_actor.default_throttle_ms,
  )
}

pub fn default_ha_poller_deps() -> HaPollerDeps {
  HaPollerDeps(send_after: timer.real_send_after)
}

/// Handle to the running supervisor
pub opaque type Supervisor {
  Supervisor(
    pid: Pid,
    house_mode_subject: Subject(house_mode_actor.Message),
    state_aggregator_name: Name(state_aggregator_actor.Message),
    ha_poller_subject: Subject(ha_poller_actor.Message),
    ha_command_name: Name(ha_command_actor.Message),
    heating_control_name: Name(heating_control_actor.Message),
    boiler_adapter_name: Name(heating_control_actor.BoilerCommand),
    heating_adapter_name: Name(room_actor.HeatingControlMessage),
    event_router_subject: Subject(ha_poller_actor.PollerEvent),
    rooms_supervisor: RoomsSupervisor,
  )
}

/// Reference to a running actor with its PID
pub type ActorRef(msg) {
  ActorRef(pid: Pid, subject: Subject(msg))
}

/// Default debounce interval for HA commands in milliseconds
const default_ha_command_debounce_ms = 5000

/// Shutdown the supervisor and ALL its actors.
///
/// This properly terminates all manually-started actors that are not
/// directly supervised by the OTP supervisor. Without this, those actors
/// would survive the supervisor termination (see dh-33jq.76).
pub fn shutdown(sup: Supervisor) -> Nil {
  // 1. Send graceful Shutdown to actors that support it
  process.send(sup.house_mode_subject, house_mode_actor.Shutdown)
  process.send(
    process.named_subject(sup.ha_command_name),
    ha_command_actor.Shutdown,
  )

  // 2. Kill actors that don't have Shutdown message (unlink first to avoid crash propagation)
  // HaPollerActor
  case process.subject_owner(sup.ha_poller_subject) {
    Ok(pid) -> {
      process.unlink(pid)
      process.send_abnormal_exit(pid, "shutdown")
    }
    Error(_) -> Nil
  }

  // HeatingControlActor
  case process.named(sup.heating_control_name) {
    Ok(pid) -> {
      process.unlink(pid)
      process.send_abnormal_exit(pid, "shutdown")
    }
    Error(_) -> Nil
  }

  // BoilerCommandAdapterActor
  case process.named(sup.boiler_adapter_name) {
    Ok(pid) -> {
      process.unlink(pid)
      process.send_abnormal_exit(pid, "shutdown")
    }
    Error(_) -> Nil
  }

  // HeatingControlAdapterActor
  case process.named(sup.heating_adapter_name) {
    Ok(pid) -> {
      process.unlink(pid)
      process.send_abnormal_exit(pid, "shutdown")
    }
    Error(_) -> Nil
  }

  // EventRouterActor
  case process.subject_owner(sup.event_router_subject) {
    Ok(pid) -> {
      process.unlink(pid)
      process.send_abnormal_exit(pid, "shutdown")
    }
    Error(_) -> Nil
  }

  // 3. Kill all room actors
  rooms_supervisor.get_room_supervisors(sup.rooms_supervisor)
  |> list.each(fn(room_sup) {
    // Kill room actor
    case rooms_supervisor.get_room_actor(room_sup) {
      Ok(ref) -> {
        process.unlink(ref.pid)
        process.send_abnormal_exit(ref.pid, "shutdown")
      }
      Error(_) -> Nil
    }

    // Kill decision actor
    case rooms_supervisor.get_decision_actor(room_sup) {
      Ok(ref) -> {
        process.unlink(ref.pid)
        process.send_abnormal_exit(ref.pid, "shutdown")
      }
      Error(_) -> Nil
    }

    // Kill TRV actors
    rooms_supervisor.get_trv_actors(room_sup)
    |> list.each(fn(trv_ref) {
      process.unlink(trv_ref.pid)
      process.send_abnormal_exit(trv_ref.pid, "shutdown")
    })
  })

  // 4. Finally kill the OTP supervisor (this will also kill StateAggregatorActor)
  process.unlink(sup.pid)
  process.send_abnormal_exit(sup.pid, "shutdown")

  // Give processes time to terminate and unregister names
  process.sleep(50)
}

// =============================================================================
// Start
// =============================================================================

/// Error type for starting the supervisor
pub type StartError {
  SupervisorStartError(actor.StartError)
  RoomsStartError(rooms_supervisor.StartError)
}

/// Start the Deep Heating supervision tree.
///
/// Starts the following actors:
/// - HouseModeActor (manages house mode state)
/// - StateAggregatorActor (aggregates room states for UI)
/// - HaCommandActor (sends commands to Home Assistant)
/// - HeatingControlActor (controls boiler based on room heating demand)
/// - RoomsSupervisor (creates per-room actor trees from HomeConfig)
/// - EventRouterActor (routes poller events to appropriate actors)
/// - HaPollerActor (polls Home Assistant for updates)
pub fn start(config: Config) -> Result(actor.Started(Supervisor), StartError) {
  // Create names for our actors so we can look them up later
  // Use prefix if provided (for test isolation)
  let prefix = case config.name_prefix {
    Some(p) -> p <> "_"
    None -> ""
  }
  let house_mode_name = process.new_name(prefix <> "deep_heating_house_mode")
  let state_aggregator_name =
    process.new_name(prefix <> "deep_heating_state_aggregator")
  let ha_poller_name = process.new_name(prefix <> "deep_heating_ha_poller")
  let ha_command_name = process.new_name(prefix <> "deep_heating_ha_command")
  let heating_control_name =
    process.new_name(prefix <> "deep_heating_heating_control")
  let heating_control_adapter_name =
    process.new_name(prefix <> "deep_heating_heating_control_adapter")
  let boiler_adapter_name =
    process.new_name(prefix <> "deep_heating_boiler_adapter")

  // Build and start the main supervision tree
  // Note: Most actors are started manually after supervision
  // to capture their actual Subjects (named_subject doesn't work for Gleam actors)
  let supervisor_result =
    supervisor.new(supervisor.OneForOne)
    |> supervisor.add(state_aggregator_actor.child_spec_with_options(
      state_aggregator_name,
      config.adjustments_path,
      config.state_aggregator_deps.send_after,
      config.state_aggregator_deps.throttle_ms,
    ))
    |> supervisor.start

  case supervisor_result {
    Error(e) -> Error(SupervisorStartError(e))
    Ok(started) -> {
      // Get the state aggregator subject for room actor registration
      let state_aggregator_subject =
        process.named_subject(state_aggregator_name)

      // Start HouseModeActor manually to capture its actual Subject
      // Use provided time_provider or default to real time
      let time_provider = case config.time_provider {
        Some(tp) -> tp
        None -> house_mode_actor.now
      }
      case
        house_mode_actor.start_named_with_options(
          name: house_mode_name,
          get_now: time_provider,
          timer_interval_ms: house_mode_actor.default_timer_interval_ms,
          send_after: config.house_mode_deps.send_after,
        )
      {
        Error(e) -> Error(SupervisorStartError(e))
        Ok(house_mode_started) -> {
          let house_mode_subject = house_mode_started.data

          // Start command actor: HaCommandActor for production, LoggingCommandActor for dry-run
          let command_actor_result = case config.dry_run {
            True -> {
              log.info(
                "[DRY RUN] Starting in dry-run mode - commands will be logged, not sent to Home Assistant",
              )
              logging_command_actor.start_named(
                name: ha_command_name,
                api_spy: process.new_subject(),
              )
            }
            False -> {
              ha_command_actor.start_named_with_options(
                name: ha_command_name,
                ha_client: config.ha_client,
                api_spy: process.new_subject(),
                debounce_ms: config.ha_command_deps.debounce_ms,
                skip_http: False,
                send_after: config.ha_command_deps.send_after,
              )
            }
          }
          case command_actor_result {
            Error(e) -> Error(SupervisorStartError(e))
            Ok(_ha_command_started) -> {
              // Load initial adjustments from environment
              let initial_adjustments =
                room_adjustments.load_from_env()
                |> result.unwrap([])

              // Start adapter actor that converts domain BoilerCommand → ha_command_actor.Message
              case
                boiler_command_adapter_actor.start_named(
                  name: boiler_adapter_name,
                  ha_command_name: ha_command_name,
                )
              {
                Error(e) -> Error(SupervisorStartError(e))
                Ok(boiler_adapter_started) -> {
                  let boiler_commands = boiler_adapter_started.data

                  // Start HeatingControlActor - rooms need its subject to send updates
                  case
                    heating_control_actor.start_named(
                      heating_control_name,
                      config.home_config.heating_id,
                      boiler_commands,
                    )
                  {
                    Error(e) -> Error(SupervisorStartError(e))
                    Ok(heating_started) -> {
                      // Start adapter actor that converts room_actor.HeatingControlMessage → heating_control_actor.Message
                      // Uses name-based lookup for heating_control_actor to survive restarts
                      case
                        heating_control_adapter_actor.start_named(
                          name: heating_control_adapter_name,
                          heating_control_name: heating_control_name,
                        )
                      {
                        Error(e) -> Error(SupervisorStartError(e))
                        Ok(heating_adapter_started) -> {
                          let heating_control_for_rooms =
                            heating_adapter_started.data

                          // Start rooms supervisor with the HomeConfig - now with heating_control wiring
                          case
                            rooms_supervisor.start(
                              config: config.home_config,
                              state_aggregator: state_aggregator_subject,
                              ha_command_name: ha_command_name,
                              house_mode: house_mode_subject,
                              heating_control: Some(heating_control_for_rooms),
                              initial_adjustments: initial_adjustments,
                              room_send_after: config.room_actor_deps.send_after,
                            )
                          {
                            Error(e) -> Error(RoomsStartError(e))
                            Ok(rooms_sup) -> {
                              // Build registries from RoomsSupervisor
                              let trv_registry =
                                build_trv_registry(
                                  rooms_sup,
                                  config.home_config,
                                )
                              let sensor_registry =
                                build_sensor_registry(
                                  rooms_sup,
                                  config.home_config,
                                )

                              // Start EventRouterActor (reuses house_mode_subject from above)
                              let router_config =
                                event_router_actor.Config(
                                  house_mode_actor: house_mode_subject,
                                  trv_registry: trv_registry,
                                  sensor_registry: sensor_registry,
                                  heating_control_actor: option.Some(
                                    heating_started.data,
                                  ),
                                )

                              case event_router_actor.start(router_config) {
                                Error(_) -> {
                                  // For now, treat router start failure as a supervisor error
                                  Error(SupervisorStartError(actor.InitTimeout))
                                }
                                Ok(event_router_subject) -> {
                                  // Start HaPollerActor with the EventRouter's subject as event_spy
                                  case
                                    ha_poller_actor.start_named_with_send_after(
                                      name: ha_poller_name,
                                      ha_client: config.ha_client,
                                      config: config.poller_config,
                                      event_spy: event_router_subject,
                                      send_after: config.ha_poller_deps.send_after,
                                    )
                                  {
                                    Error(e) -> Error(SupervisorStartError(e))
                                    Ok(poller_started) -> {
                                      let sup =
                                        Supervisor(
                                          pid: started.pid,
                                          house_mode_subject: house_mode_subject,
                                          state_aggregator_name: state_aggregator_name,
                                          ha_poller_subject: poller_started.data,
                                          ha_command_name: ha_command_name,
                                          heating_control_name: heating_control_name,
                                          boiler_adapter_name: boiler_adapter_name,
                                          heating_adapter_name: heating_control_adapter_name,
                                          event_router_subject: event_router_subject,
                                          rooms_supervisor: rooms_sup,
                                        )
                                      Ok(actor.Started(
                                        pid: started.pid,
                                        data: sup,
                                      ))
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
pub fn get_rooms_supervisor(sup: Supervisor) -> Result(RoomsSupervisor, Nil) {
  Ok(sup.rooms_supervisor)
}

/// Get a reference to the HeatingControlActor
pub fn get_heating_control_actor(
  sup: Supervisor,
) -> Result(ActorRef(heating_control_actor.Message), Nil) {
  case process.named(sup.heating_control_name) {
    Ok(pid) -> {
      let subject = process.named_subject(sup.heating_control_name)
      Ok(ActorRef(pid: pid, subject: subject))
    }
    Error(_) -> Error(Nil)
  }
}

/// Get the HaPollerActor's subject for sending messages (e.g., PollNow)
pub fn get_ha_poller_subject(
  sup: Supervisor,
) -> Subject(ha_poller_actor.Message) {
  sup.ha_poller_subject
}

/// Get the current house mode by querying the HouseModeActor
pub fn get_current_house_mode(sup: Supervisor) -> mode.HouseMode {
  let reply = process.new_subject()
  process.send(sup.house_mode_subject, house_mode_actor.GetMode(reply))
  let assert Ok(current_mode) = process.receive(reply, 1000)
  current_mode
}

/// Get the StateAggregatorActor's subject for subscribing to state updates
pub fn get_state_aggregator_subject(
  sup: Supervisor,
) -> Subject(state_aggregator_actor.Message) {
  process.named_subject(sup.state_aggregator_name)
}
