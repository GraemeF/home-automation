import deep_heating/config/home_config.{type HomeConfig, HomeConfig, RoomConfig}
import deep_heating/entity_id
import deep_heating/home_assistant/client as home_assistant
import deep_heating/home_assistant/ha_poller_actor
import deep_heating/house_mode/house_mode_actor
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
) -> supervisor.Config {
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
) -> supervisor.Config {
  // Create spy subjects that capture timer requests (never fire them)
  let house_mode_spy = process.new_subject()
  let ha_poller_spy = process.new_subject()
  let room_actor_spy = process.new_subject()
  let ha_command_spy = process.new_subject()
  let state_aggregator_spy = process.new_subject()

  supervisor.Config(
    ha_client: ha_client,
    poller_config: poller_config,
    adjustments_path: adjustments_path,
    home_config: home_config,
    name_prefix: name_prefix,
    time_provider: time_provider,
    dry_run: False,
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

// =============================================================================
// Helper functions
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

// =============================================================================
// RoomsSupervisor wiring tests
// =============================================================================

pub fn supervisor_starts_rooms_test() {
  // When started, rooms should be created from the HomeConfig
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

  let assert Ok(started) = supervisor.start(config)

  // Get the rooms supervisor from the main supervisor
  let assert Ok(rooms_sup) = supervisor.get_rooms_supervisor(started.data)

  // Should have one room
  let room_supervisors = rooms_supervisor.get_room_supervisors(rooms_sup)
  list.length(room_supervisors) |> should.equal(1)

  // Cleanup
  supervisor.shutdown(started.data)
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

  let assert Ok(started) = supervisor.start(config)

  // Get the rooms supervisor
  let assert Ok(rooms_sup) = supervisor.get_rooms_supervisor(started.data)

  // Should be able to get room by name
  let lounge_result = rooms_supervisor.get_room_by_name(rooms_sup, "lounge")
  should.be_ok(lounge_result)

  // Cleanup
  supervisor.shutdown(started.data)
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

  let assert Ok(started) = supervisor.start(config)

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
  supervisor.shutdown(started.data)
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

  let assert Ok(started) = supervisor.start(config)

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
  supervisor.shutdown(started.data)

  // The room should have the adjustment from the persisted file
  state.adjustment |> should.equal(1.5)
}

// =============================================================================
// HeatingControlActor wiring tests
// =============================================================================

pub fn supervisor_has_heating_control_actor_test() {
  // When started, supervisor should have HeatingControlActor
  let ha_client = home_assistant.HaClient("http://localhost:8123", "test-token")
  let home_config = make_test_home_config()
  let poller_config = create_test_poller_config()
  let config =
    make_test_supervisor_config(ha_client, poller_config, home_config, "has_hc")

  let assert Ok(started) = supervisor.start(config)

  // Get the heating control actor from the supervisor
  let result = supervisor.get_heating_control_actor(started.data)
  should.be_ok(result)

  // Cleanup
  supervisor.shutdown(started.data)
}

pub fn heating_control_actor_is_alive_test() {
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

  let assert Ok(started) = supervisor.start(config)

  let assert Ok(heating_control) =
    supervisor.get_heating_control_actor(started.data)
  process.is_alive(heating_control.pid) |> should.be_true

  // Cleanup
  supervisor.shutdown(started.data)
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

  let assert Ok(started) = supervisor.start(config)

  // Verify all actors are alive
  let assert Ok(rooms_sup) = supervisor.get_rooms_supervisor(started.data)
  let room_supervisors = rooms_supervisor.get_room_supervisors(rooms_sup)
  list.length(room_supervisors) |> should.equal(1)

  // Cleanup
  supervisor.shutdown(started.data)
}

// =============================================================================
// Graceful shutdown tests (dh-33jq.66)
//
// shutdown properly terminates ALL actors started by
// start, not just the OTP-supervised ones.
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

  let assert Ok(started) = supervisor.start(config)

  let supervisor_pid = started.pid

  // Verify supervisor is alive before shutdown
  process.is_alive(supervisor_pid) |> should.be_true

  // Shutdown using the proper shutdown function
  supervisor.shutdown(started.data)
  process.sleep(100)

  // The OTP supervisor PID should be dead
  process.is_alive(supervisor_pid) |> should.be_false
}

pub fn shutdown_terminates_all_actors_test() {
  // All actors should be properly terminated when shutdown is called.
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

  let assert Ok(started) = supervisor.start(config)

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
  supervisor.shutdown(started.data)
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
  let assert Ok(started1) = supervisor.start(config1)

  // Shutdown first instance using proper shutdown function
  supervisor.shutdown(started1.data)
  process.sleep(100)

  // Second instance with same prefix should start successfully
  let config2 =
    make_test_supervisor_config(
      ha_client,
      poller_config,
      home_config,
      name_prefix,
    )
  let result2 = supervisor.start(config2)

  should.be_ok(result2)

  // Cleanup
  case result2 {
    Ok(started2) -> {
      supervisor.shutdown(started2.data)
    }
    Error(_) -> Nil
  }
}

// =============================================================================
// Dry-run mode tests (dh-33jq.85)
// =============================================================================

pub fn supervisor_starts_in_dry_run_mode_test() {
  // When dry_run is true, supervisor should start LoggingCommandActor
  // instead of HaCommandActor
  let ha_client = home_assistant.HaClient("http://localhost:8123", "test-token")
  let home_config = make_test_home_config()
  let poller_config = create_test_poller_config()
  let config =
    make_test_supervisor_config_with_dry_run(
      ha_client,
      poller_config,
      home_config,
      "dry_run_test",
      True,
    )

  let assert Ok(started) = supervisor.start(config)

  // Supervisor should start successfully in dry-run mode
  process.is_alive(started.pid) |> should.be_true

  // Cleanup
  supervisor.shutdown(started.data)
}

/// Create config with dry_run option
fn make_test_supervisor_config_with_dry_run(
  ha_client: home_assistant.HaClient,
  poller_config: ha_poller_actor.PollerConfig,
  home_config: HomeConfig,
  name_prefix: String,
  dry_run: Bool,
) -> supervisor.Config {
  // Create spy subjects that capture timer requests (never fire them)
  let house_mode_spy = process.new_subject()
  let ha_poller_spy = process.new_subject()
  let room_actor_spy = process.new_subject()
  let ha_command_spy = process.new_subject()
  let state_aggregator_spy = process.new_subject()

  supervisor.Config(
    ha_client: ha_client,
    poller_config: poller_config,
    adjustments_path: test_adjustments_path,
    home_config: home_config,
    name_prefix: Some(name_prefix),
    time_provider: None,
    dry_run: dry_run,
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

  let assert Ok(started) = supervisor.start(config)

  let supervisor_pid = started.pid

  // Now shutdown using proper shutdown function
  supervisor.shutdown(started.data)

  // Shutdown should complete within 200ms even though actors have 63s timers
  // This proves timers don't block process termination
  process.sleep(150)

  // Should be dead by now
  process.is_alive(supervisor_pid) |> should.be_false
}
