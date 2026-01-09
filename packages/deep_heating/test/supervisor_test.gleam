import deep_heating/config/home_config.{type HomeConfig, HomeConfig, RoomConfig}
import deep_heating/entity_id
import deep_heating/home_assistant/client as home_assistant
import deep_heating/home_assistant/ha_command_actor
import deep_heating/home_assistant/ha_poller_actor
import deep_heating/house_mode/house_mode_actor
import deep_heating/mode
import deep_heating/rooms/room_actor
import deep_heating/rooms/rooms_supervisor
import deep_heating/scheduling/schedule
import deep_heating/supervisor
import deep_heating/temperature
import deep_heating/timer
import envoy
import gleam/erlang/process
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set
import gleeunit/should
import simplifile

/// Test adjustments path - using /tmp for test safety
const test_adjustments_path = "/tmp/deep_heating_test_adjustments.json"

/// Create config with a custom name prefix (for test isolation)
fn make_test_supervisor_config(
  ha_client: home_assistant.HaClient,
  poller_config: ha_poller_actor.PollerConfig,
  home_config: HomeConfig,
  name_prefix: String,
) -> supervisor.SupervisorConfigWithRooms {
  make_test_supervisor_config_full(
    ha_client,
    poller_config,
    home_config,
    None,
    test_adjustments_path,
    Some(name_prefix),
  )
}

/// Create config with all options
fn make_test_supervisor_config_full(
  ha_client: home_assistant.HaClient,
  poller_config: ha_poller_actor.PollerConfig,
  home_config: HomeConfig,
  time_provider: Option(house_mode_actor.TimeProvider),
  adjustments_path: String,
  name_prefix: Option(String),
) -> supervisor.SupervisorConfigWithRooms {
  // Create spy subjects that capture timer requests (never fire them)
  let house_mode_spy = process.new_subject()
  let ha_poller_spy = process.new_subject()
  let room_actor_spy = process.new_subject()
  let ha_command_spy = process.new_subject()
  let state_aggregator_spy = process.new_subject()

  supervisor.SupervisorConfigWithRooms(
    ha_client: ha_client,
    poller_config: poller_config,
    adjustments_path: adjustments_path,
    home_config: home_config,
    name_prefix: name_prefix,
    time_provider: time_provider,
    house_mode_deps: supervisor.HouseModeDeps(send_after: timer.spy_send_after(
      house_mode_spy,
    )),
    ha_poller_deps: supervisor.HaPollerDeps(send_after: timer.spy_send_after(
      ha_poller_spy,
    )),
    room_actor_deps: supervisor.RoomActorDeps(send_after: timer.spy_send_after(
      room_actor_spy,
    )),
    ha_command_deps: supervisor.HaCommandDeps(
      send_after: timer.spy_send_after(ha_command_spy),
      debounce_ms: 5000,
    ),
    // Use throttle_ms: 0 for immediate broadcasts in tests
    state_aggregator_deps: supervisor.StateAggregatorDeps(
      send_after: timer.spy_send_after(state_aggregator_spy),
      throttle_ms: 0,
    ),
  )
}

// Supervisor startup tests

pub fn supervisor_starts_successfully_test() {
  // The top-level supervisor should start and return Ok with a Started record
  let assert Ok(started) = supervisor.start_with_prefix(Some("starts_ok"))
  supervisor.shutdown(started.data)
}

pub fn supervisor_returns_valid_pid_test() {
  // The started supervisor should have a valid PID
  let assert Ok(started) = supervisor.start_with_prefix(Some("valid_pid"))
  // Verify the PID is alive
  process.is_alive(started.pid) |> should.be_true
  supervisor.shutdown(started.data)
}

// Child supervisor tests

pub fn supervisor_has_house_mode_actor_test() {
  // The supervisor should have started a HouseModeActor child
  let assert Ok(started) = supervisor.start_with_prefix(Some("has_house_mode"))

  // Get the house mode actor from the supervisor
  let result = supervisor.get_house_mode_actor(started.data)
  should.be_ok(result)
  supervisor.shutdown(started.data)
}

pub fn supervisor_has_state_aggregator_actor_test() {
  // The supervisor should have started a StateAggregatorActor child
  let assert Ok(started) = supervisor.start_with_prefix(Some("has_state_agg"))

  // Get the state aggregator from the supervisor
  let result = supervisor.get_state_aggregator(started.data)
  should.be_ok(result)
  supervisor.shutdown(started.data)
}

pub fn house_mode_actor_is_alive_test() {
  // The house mode actor should be running
  let assert Ok(started) = supervisor.start_with_prefix(Some("hm_alive"))
  let assert Ok(house_mode) = supervisor.get_house_mode_actor(started.data)
  process.is_alive(house_mode.pid) |> should.be_true
  supervisor.shutdown(started.data)
}

pub fn state_aggregator_actor_is_alive_test() {
  // The state aggregator actor should be running
  let assert Ok(started) = supervisor.start_with_prefix(Some("sa_alive"))
  let assert Ok(aggregator) = supervisor.get_state_aggregator(started.data)
  process.is_alive(aggregator.pid) |> should.be_true
  supervisor.shutdown(started.data)
}

// Restart behaviour tests

pub fn supervisor_restarts_crashed_house_mode_actor_test() {
  // When the house mode actor crashes, the supervisor should restart it
  let assert Ok(started) = supervisor.start_with_prefix(Some("hm_restart"))

  // Get the house mode actor's PID
  let assert Ok(house_mode) = supervisor.get_house_mode_actor(started.data)
  let original_pid = house_mode.pid

  // Verify it's alive
  process.is_alive(original_pid) |> should.be_true

  // Crash the actor by sending an abnormal exit signal
  process.send_abnormal_exit(original_pid, "test_crash")

  // Give supervisor time to restart the child
  process.sleep(100)

  // The original PID should be dead
  process.is_alive(original_pid) |> should.be_false

  // Get the house mode actor again - should be a new process
  let assert Ok(new_house_mode) = supervisor.get_house_mode_actor(started.data)

  // The new actor should be alive
  process.is_alive(new_house_mode.pid) |> should.be_true

  // The new PID should be different from the original
  should.not_equal(new_house_mode.pid, original_pid)
  supervisor.shutdown(started.data)
}

pub fn supervisor_restarts_crashed_state_aggregator_test() {
  // When the state aggregator crashes, the supervisor should restart it
  let assert Ok(started) = supervisor.start_with_prefix(Some("sa_restart"))

  // Get the aggregator's PID
  let assert Ok(aggregator) = supervisor.get_state_aggregator(started.data)
  let original_pid = aggregator.pid

  // Crash the actor
  process.send_abnormal_exit(original_pid, "test_crash")

  // Give supervisor time to restart
  process.sleep(100)

  // Get the aggregator again
  let assert Ok(new_aggregator) = supervisor.get_state_aggregator(started.data)

  // Should be alive with a new PID
  process.is_alive(new_aggregator.pid) |> should.be_true
  should.not_equal(new_aggregator.pid, original_pid)
  supervisor.shutdown(started.data)
}

// =============================================================================
// HaPollerActor tests
// =============================================================================

fn create_test_poller_config() -> ha_poller_actor.PollerConfig {
  let assert Ok(heating_id) =
    entity_id.climate_entity_id("climate.main_heating")
  ha_poller_actor.PollerConfig(
    poll_interval_ms: 5000,
    heating_entity_id: heating_id,
    sleep_button_entity_id: "input_button.goodnight",
    managed_trv_ids: set.new(),
    managed_sensor_ids: set.new(),
  )
}

pub fn supervisor_has_ha_poller_actor_test() {
  // When started with config, supervisor should have HaPollerActor child
  let assert Ok(started) =
    supervisor.start_with_config(supervisor.SupervisorConfig(
      ha_client: home_assistant.HaClient("http://localhost:8123", "test-token"),
      poller_config: create_test_poller_config(),
      adjustments_path: test_adjustments_path,
      name_prefix: Some("has_ha_poller"),
    ))

  // Get the ha poller actor from the supervisor
  let result = supervisor.get_ha_poller(started.data)
  should.be_ok(result)
  supervisor.shutdown(started.data)
}

pub fn ha_poller_actor_is_alive_test() {
  // The HaPollerActor should be running
  let assert Ok(started) =
    supervisor.start_with_config(supervisor.SupervisorConfig(
      ha_client: home_assistant.HaClient("http://localhost:8123", "test-token"),
      poller_config: create_test_poller_config(),
      adjustments_path: test_adjustments_path,
      name_prefix: Some("ha_poller_alive"),
    ))

  let assert Ok(ha_poller) = supervisor.get_ha_poller(started.data)
  process.is_alive(ha_poller.pid) |> should.be_true
  supervisor.shutdown(started.data)
}

pub fn supervisor_restarts_crashed_ha_poller_actor_test() {
  // When the HaPollerActor crashes, the supervisor should restart it
  let assert Ok(started) =
    supervisor.start_with_config(supervisor.SupervisorConfig(
      ha_client: home_assistant.HaClient("http://localhost:8123", "test-token"),
      poller_config: create_test_poller_config(),
      adjustments_path: test_adjustments_path,
      name_prefix: Some("ha_poller_restart"),
    ))

  // Get the HaPollerActor's PID
  let assert Ok(ha_poller) = supervisor.get_ha_poller(started.data)
  let original_pid = ha_poller.pid

  // Verify it's alive
  process.is_alive(original_pid) |> should.be_true

  // Crash the actor by sending an abnormal exit signal
  process.send_abnormal_exit(original_pid, "test_crash")

  // Give supervisor time to restart the child
  process.sleep(100)

  // The original PID should be dead
  process.is_alive(original_pid) |> should.be_false

  // Get the HaPollerActor again - should be a new process
  let assert Ok(new_ha_poller) = supervisor.get_ha_poller(started.data)

  // The new actor should be alive
  process.is_alive(new_ha_poller.pid) |> should.be_true

  // The new PID should be different from the original
  should.not_equal(new_ha_poller.pid, original_pid)
  supervisor.shutdown(started.data)
}

// =============================================================================
// HaCommandActor tests
// =============================================================================

pub fn supervisor_has_ha_command_actor_test() {
  // When started with config, supervisor should have HaCommandActor child
  let assert Ok(started) =
    supervisor.start_with_config(supervisor.SupervisorConfig(
      ha_client: home_assistant.HaClient("http://localhost:8123", "test-token"),
      poller_config: create_test_poller_config(),
      adjustments_path: test_adjustments_path,
      name_prefix: Some("has_ha_cmd"),
    ))

  // Get the ha command actor from the supervisor
  let result = supervisor.get_ha_command_actor(started.data)
  should.be_ok(result)
  supervisor.shutdown(started.data)
}

pub fn ha_command_actor_is_alive_test() {
  // The HaCommandActor should be running
  let assert Ok(started) =
    supervisor.start_with_config(supervisor.SupervisorConfig(
      ha_client: home_assistant.HaClient("http://localhost:8123", "test-token"),
      poller_config: create_test_poller_config(),
      adjustments_path: test_adjustments_path,
      name_prefix: Some("ha_cmd_alive"),
    ))

  let assert Ok(ha_command) = supervisor.get_ha_command_actor(started.data)
  process.is_alive(ha_command.pid) |> should.be_true
  supervisor.shutdown(started.data)
}

pub fn ha_command_actor_responds_to_messages_test() {
  // The HaCommandActor should process messages
  let assert Ok(started) =
    supervisor.start_with_config(supervisor.SupervisorConfig(
      ha_client: home_assistant.HaClient("http://localhost:8123", "test-token"),
      poller_config: create_test_poller_config(),
      adjustments_path: test_adjustments_path,
      name_prefix: Some("ha_cmd_msg"),
    ))

  let assert Ok(ha_command) = supervisor.get_ha_command_actor(started.data)
  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  // Send a message to the actor (it won't actually call HA since we're in test)
  process.send(
    ha_command.subject,
    ha_command_actor.SetTrvAction(
      entity_id: trv_id,
      mode: mode.HvacHeat,
      target: temperature.temperature(21.0),
    ),
  )

  // Just verify the actor didn't crash - still alive after message
  process.sleep(10)
  process.is_alive(ha_command.pid) |> should.be_true
  supervisor.shutdown(started.data)
}

// =============================================================================
// RoomsSupervisor wiring tests
// =============================================================================

fn make_test_schedule() -> schedule.WeekSchedule {
  // Simple schedule: 20°C all day every day
  let assert Ok(time) = schedule.time_of_day(0, 0)
  let entry =
    schedule.ScheduleEntry(
      start: time,
      target_temperature: temperature.temperature(20.0),
    )
  let day = [entry]
  schedule.WeekSchedule(
    monday: day,
    tuesday: day,
    wednesday: day,
    thursday: day,
    friday: day,
    saturday: day,
    sunday: day,
  )
}

fn make_test_home_config() -> HomeConfig {
  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")
  let assert Ok(sensor_id) = entity_id.sensor_entity_id("sensor.lounge_temp")
  let assert Ok(sleep_switch) =
    entity_id.goodnight_entity_id("input_button.goodnight")
  let assert Ok(heating_id) = entity_id.climate_entity_id("climate.heating")

  HomeConfig(
    rooms: [
      RoomConfig(
        name: "lounge",
        temperature_sensor_entity_id: Some(sensor_id),
        climate_entity_ids: [trv_id],
        schedule: Some(make_test_schedule()),
      ),
    ],
    sleep_switch_id: sleep_switch,
    heating_id: heating_id,
  )
}

pub fn supervisor_starts_rooms_with_home_config_test() {
  // When started with config including HomeConfig, rooms should be created
  let ha_client = home_assistant.HaClient("http://localhost:8123", "test-token")
  let home_config = make_test_home_config()
  let poller_config = create_test_poller_config()

  let config =
    make_test_supervisor_config(
      ha_client,
      poller_config,
      home_config,
      "starts_rooms",
    )

  let assert Ok(started) = supervisor.start_with_home_config(config)

  // Get the rooms supervisor from the main supervisor
  let assert Ok(rooms_sup) = supervisor.get_rooms_supervisor(started.data)

  // Should have one room
  let room_supervisors = rooms_supervisor.get_room_supervisors(rooms_sup)
  list.length(room_supervisors) |> should.equal(1)

  // Cleanup
  supervisor.shutdown_with_rooms(started.data)
}

pub fn supervisor_rooms_are_accessible_by_name_test() {
  // Rooms should be accessible by name through the supervisor
  let ha_client = home_assistant.HaClient("http://localhost:8123", "test-token")
  let home_config = make_test_home_config()
  let poller_config = create_test_poller_config()
  let config =
    make_test_supervisor_config(
      ha_client,
      poller_config,
      home_config,
      "rooms_by_name",
    )

  let assert Ok(started) = supervisor.start_with_home_config(config)

  // Get the rooms supervisor
  let assert Ok(rooms_sup) = supervisor.get_rooms_supervisor(started.data)

  // Should be able to get room by name
  let lounge_result = rooms_supervisor.get_room_by_name(rooms_sup, "lounge")
  should.be_ok(lounge_result)

  // Cleanup
  supervisor.shutdown_with_rooms(started.data)
}

pub fn supervisor_room_actors_are_alive_test() {
  // Room actors started by the supervisor should be alive and responding
  let ha_client = home_assistant.HaClient("http://localhost:8123", "test-token")
  let home_config = make_test_home_config()
  let poller_config = create_test_poller_config()
  let config =
    make_test_supervisor_config(
      ha_client,
      poller_config,
      home_config,
      "room_alive",
    )

  let assert Ok(started) = supervisor.start_with_home_config(config)

  // Get the rooms supervisor and lounge room
  let assert Ok(rooms_sup) = supervisor.get_rooms_supervisor(started.data)
  let assert Ok(lounge) = rooms_supervisor.get_room_by_name(rooms_sup, "lounge")

  // Get the room actor and query its state
  let assert Ok(room_actor_ref) = rooms_supervisor.get_room_actor(lounge)
  let reply = process.new_subject()
  process.send(room_actor_ref.subject, room_actor.GetState(reply))

  // Should respond with state showing the room name
  let assert Ok(state) = process.receive(reply, 1000)
  state.name |> should.equal("lounge")

  // Cleanup
  supervisor.shutdown_with_rooms(started.data)
}

// =============================================================================
// Room adjustments loading on startup tests
// =============================================================================

pub fn supervisor_loads_room_adjustments_from_env_test() {
  // When ROOM_ADJUSTMENTS_PATH is set with persisted adjustments,
  // RoomActors should start with those adjustments applied
  let test_path = "/tmp/test_supervisor_adjustments.json"
  let json = "[{\"roomName\": \"lounge\", \"adjustment\": 1.5}]"
  let assert Ok(_) = simplifile.write(test_path, json)

  // Set the environment variable
  envoy.set("ROOM_ADJUSTMENTS_PATH", test_path)

  let ha_client = home_assistant.HaClient("http://localhost:8123", "test-token")
  let home_config = make_test_home_config()
  let poller_config = create_test_poller_config()
  let config =
    make_test_supervisor_config_full(
      ha_client,
      poller_config,
      home_config,
      None,
      test_path,
      Some("load_adj"),
    )

  let assert Ok(started) = supervisor.start_with_home_config(config)

  // Get the lounge room actor and query its state
  let assert Ok(rooms_sup) = supervisor.get_rooms_supervisor(started.data)
  let assert Ok(lounge) = rooms_supervisor.get_room_by_name(rooms_sup, "lounge")
  let assert Ok(room_actor_ref) = rooms_supervisor.get_room_actor(lounge)
  let reply = process.new_subject()
  process.send(room_actor_ref.subject, room_actor.GetState(reply))
  let assert Ok(state) = process.receive(reply, 1000)

  // Cleanup
  envoy.unset("ROOM_ADJUSTMENTS_PATH")
  let _ = simplifile.delete(test_path)
  supervisor.shutdown_with_rooms(started.data)

  // The room should have the adjustment from the persisted file
  state.adjustment |> should.equal(1.5)
}

// =============================================================================
// HeatingControlActor wiring tests
// =============================================================================

pub fn supervisor_has_heating_control_actor_when_started_with_home_config_test() {
  // When started with home config, supervisor should have HeatingControlActor
  let ha_client = home_assistant.HaClient("http://localhost:8123", "test-token")
  let home_config = make_test_home_config()
  let poller_config = create_test_poller_config()
  let config =
    make_test_supervisor_config(ha_client, poller_config, home_config, "has_hc")

  let assert Ok(started) = supervisor.start_with_home_config(config)

  // Get the heating control actor from the supervisor
  let result = supervisor.get_heating_control_actor(started.data)
  should.be_ok(result)

  // Cleanup
  supervisor.shutdown_with_rooms(started.data)
}

pub fn heating_control_actor_is_alive_when_started_with_home_config_test() {
  // The HeatingControlActor should be running
  let ha_client = home_assistant.HaClient("http://localhost:8123", "test-token")
  let home_config = make_test_home_config()
  let poller_config = create_test_poller_config()
  let config =
    make_test_supervisor_config(
      ha_client,
      poller_config,
      home_config,
      "hc_alive",
    )

  let assert Ok(started) = supervisor.start_with_home_config(config)

  let assert Ok(heating_control) =
    supervisor.get_heating_control_actor(started.data)
  process.is_alive(heating_control.pid) |> should.be_true

  // Cleanup
  supervisor.shutdown_with_rooms(started.data)
}

// =============================================================================
// Instant timer injection tests
// =============================================================================

pub fn supervisor_accepts_timer_deps_config_test() {
  // The supervisor should start successfully with timer deps
  let ha_client = home_assistant.HaClient("http://localhost:8123", "test-token")
  let home_config = make_test_home_config()
  let poller_config = create_test_poller_config()
  let config =
    make_test_supervisor_config(
      ha_client,
      poller_config,
      home_config,
      "timer_deps_test",
    )

  let assert Ok(started) = supervisor.start_with_home_config(config)

  // Verify all actors are alive
  let assert Ok(rooms_sup) = supervisor.get_rooms_supervisor(started.data)
  let room_supervisors = rooms_supervisor.get_room_supervisors(rooms_sup)
  list.length(room_supervisors) |> should.equal(1)

  // Cleanup
  supervisor.shutdown_with_rooms(started.data)
}

// =============================================================================
// Graceful shutdown tests (dh-33jq.66)
//
// shutdown_with_rooms properly terminates ALL actors started by
// start_with_home_config, not just the OTP-supervised ones.
// This was fixed as part of dh-33jq.76.
// =============================================================================

pub fn shutdown_terminates_otp_supervisor_test() {
  // After supervisor shutdown, the OTP supervisor process should be dead
  let ha_client = home_assistant.HaClient("http://localhost:8123", "test-token")
  let home_config = make_test_home_config()
  let poller_config = create_test_poller_config()
  let config =
    make_test_supervisor_config(
      ha_client,
      poller_config,
      home_config,
      "shutdown_test_1",
    )

  let assert Ok(started) = supervisor.start_with_home_config(config)

  let supervisor_pid = started.pid

  // Verify supervisor is alive before shutdown
  process.is_alive(supervisor_pid) |> should.be_true

  // Shutdown using the proper shutdown function
  supervisor.shutdown_with_rooms(started.data)
  process.sleep(100)

  // The OTP supervisor PID should be dead
  process.is_alive(supervisor_pid) |> should.be_false
}

pub fn shutdown_with_rooms_terminates_all_actors_test() {
  // All actors should be properly terminated when shutdown_with_rooms is called.
  // This verifies the fix for dh-33jq.76.
  let ha_client = home_assistant.HaClient("http://localhost:8123", "test-token")
  let home_config = make_test_home_config()
  let poller_config = create_test_poller_config()
  let config =
    make_test_supervisor_config(
      ha_client,
      poller_config,
      home_config,
      "shutdown_test_2",
    )

  let assert Ok(started) = supervisor.start_with_home_config(config)

  let supervisor_pid = started.pid

  // Get manually-started actors' PIDs to verify they die
  let assert Ok(heating_control) =
    supervisor.get_heating_control_actor(started.data)
  let heating_pid = heating_control.pid

  // Get PIDs from available subjects
  let ha_poller_subject = supervisor.get_ha_poller_subject(started.data)
  let ha_poller_pid =
    process.subject_owner(ha_poller_subject)
    |> should.be_ok

  let state_agg_subject = supervisor.get_state_aggregator_subject(started.data)
  let state_agg_pid =
    process.subject_owner(state_agg_subject)
    |> should.be_ok

  // All should be alive before shutdown
  process.is_alive(supervisor_pid) |> should.be_true
  process.is_alive(heating_pid) |> should.be_true
  process.is_alive(ha_poller_pid) |> should.be_true
  process.is_alive(state_agg_pid) |> should.be_true

  // Call the proper shutdown function
  supervisor.shutdown_with_rooms(started.data)
  process.sleep(100)

  // ALL actors should be dead after proper shutdown
  process.is_alive(supervisor_pid) |> should.be_false
  process.is_alive(heating_pid) |> should.be_false
  process.is_alive(ha_poller_pid) |> should.be_false
  process.is_alive(state_agg_pid) |> should.be_false
}

pub fn shutdown_allows_restart_with_same_names_test() {
  // After shutdown, we should be able to start a new supervisor with the same names
  // This verifies that process names are properly unregistered during shutdown
  let ha_client = home_assistant.HaClient("http://localhost:8123", "test-token")
  let home_config = make_test_home_config()
  let poller_config = create_test_poller_config()

  // Use the same prefix for both instances to test name cleanup
  let name_prefix = "restart_test"

  // First instance
  let config1 =
    make_test_supervisor_config(
      ha_client,
      poller_config,
      home_config,
      name_prefix,
    )
  let assert Ok(started1) = supervisor.start_with_home_config(config1)

  // Shutdown first instance using proper shutdown function
  supervisor.shutdown_with_rooms(started1.data)
  process.sleep(100)

  // Second instance with same prefix should start successfully
  let config2 =
    make_test_supervisor_config(
      ha_client,
      poller_config,
      home_config,
      name_prefix,
    )
  let result2 = supervisor.start_with_home_config(config2)

  should.be_ok(result2)

  // Cleanup
  case result2 {
    Ok(started2) -> {
      supervisor.shutdown_with_rooms(started2.data)
    }
    Error(_) -> Nil
  }
}

pub fn shutdown_is_fast_test() {
  // Shutdown should complete quickly without blocking
  // The supervisor has actors with timers (HouseModeActor 63s, RoomActor 63s, etc.)
  // OTP supervisor termination should not wait for these timers
  let ha_client = home_assistant.HaClient("http://localhost:8123", "test-token")
  let home_config = make_test_home_config()
  let poller_config = create_test_poller_config()
  let config =
    make_test_supervisor_config(
      ha_client,
      poller_config,
      home_config,
      "shutdown_timing_test",
    )

  let assert Ok(started) = supervisor.start_with_home_config(config)

  let supervisor_pid = started.pid

  // Now shutdown using proper shutdown function
  supervisor.shutdown_with_rooms(started.data)

  // Shutdown should complete within 200ms even though actors have 63s timers
  // This proves timers don't block process termination
  process.sleep(150)

  // Should be dead by now
  process.is_alive(supervisor_pid) |> should.be_false
}
