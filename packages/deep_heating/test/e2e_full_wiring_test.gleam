//// End-to-end test proving the full Deep Heating wiring works.
////
//// This test validates the complete application flow:
//// - HaPollerActor polls and parses correctly
//// - Events route to correct actors
//// - HeatingControlActor evaluates demand and sends commands
//// - HaCommandActor forwards commands to HA
//// - RoomsSupervisor starts rooms from config
//// - StateAggregatorActor aggregates state
////
//// If any wiring is missing, this test fails.

import deep_heating/config/home_config.{type HomeConfig, HomeConfig, RoomConfig}
import deep_heating/entity_id
import deep_heating/home_assistant/client.{HaClient}
import deep_heating/home_assistant/ha_command_actor
import deep_heating/home_assistant/ha_poller_actor
import deep_heating/house_mode/house_mode_actor
import deep_heating/mode
import deep_heating/rooms/room_actor
import deep_heating/scheduling/schedule
import deep_heating/state.{type DeepHeatingState}
import deep_heating/state/state_aggregator_actor
import deep_heating/supervisor
import deep_heating/temperature
import deep_heating/timer
import fake_ha_server.{ClimateEntityState, SensorEntityState}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set
import gleeunit/should

// =============================================================================
// Test constants
// =============================================================================

/// Base port for e2e tests (use different ports per test to avoid conflicts)
const base_port = 9500

/// Test HA auth token
const test_token = "e2e-test-token"

/// Test adjustments path
const test_adjustments_path = "/tmp/deep_heating_e2e_adjustments.json"

// =============================================================================
// Test infrastructure - spy subjects for controlled timers
// =============================================================================

/// Spy subjects for capturing timer requests.
/// Tests can receive from these to trigger timer messages manually.
type TestSpies {
  TestSpies(
    house_mode: Subject(timer.TimerRequest(house_mode_actor.Message)),
    room_actor: Subject(timer.TimerRequest(room_actor.Message)),
    ha_command: Subject(timer.TimerRequest(ha_command_actor.Message)),
    state_aggregator: Subject(
      timer.TimerRequest(state_aggregator_actor.Message),
    ),
    ha_poller: Subject(timer.TimerRequest(ha_poller_actor.Message)),
  )
}

/// Create spy subjects for all actor types
fn create_test_spies() -> TestSpies {
  TestSpies(
    house_mode: process.new_subject(),
    room_actor: process.new_subject(),
    ha_command: process.new_subject(),
    state_aggregator: process.new_subject(),
    ha_poller: process.new_subject(),
  )
}

/// Flush all pending timer requests from a spy, triggering them immediately.
/// Returns the number of timers that were triggered.
/// Uses timeout 0 - only flushes requests already in the mailbox.
fn flush_timer_spy(spy: Subject(timer.TimerRequest(msg))) -> Int {
  flush_timer_spy_loop(spy, 0)
}

fn flush_timer_spy_loop(
  spy: Subject(timer.TimerRequest(msg)),
  count: Int,
) -> Int {
  case process.receive(spy, 0) {
    Ok(timer.TimerRequest(subject, _delay, msg)) -> {
      process.send(subject, msg)
      flush_timer_spy_loop(spy, count + 1)
    }
    Error(_) -> count
  }
}

/// Wait for at least one timer request to arrive, then IMMEDIATELY trigger it.
/// This bypasses the actual delay - useful for testing wiring without waiting.
/// Returns Ok(count) with the number of timers triggered, or Error(Nil) if timeout.
fn wait_and_immediately_trigger_timers(
  spy: Subject(timer.TimerRequest(msg)),
  timeout_ms: Int,
) -> Result(Int, Nil) {
  case process.receive(spy, timeout_ms) {
    Ok(timer.TimerRequest(subject, _delay, msg)) -> {
      process.send(subject, msg)
      // Continue to flush any additional timers that arrived
      Ok(1 + flush_timer_spy(spy))
    }
    Error(_) -> Error(Nil)
  }
}

/// Wait for ha_command timers to arrive and IMMEDIATELY trigger ALL of them.
/// This bypasses the actual debounce delay - we're testing wiring, not timing.
/// HaCommandActor handles both TRV and heating commands, so multiple timers
/// may be scheduled. We wait for the first (with long timeout to sync), then
/// continue waiting with shorter timeouts until no more timers arrive.
fn wait_and_immediately_trigger_ha_command_timers(
  spies: TestSpies,
) -> Result(Int, Nil) {
  // First wait for at least one timer to ensure message chain has progressed
  case wait_and_immediately_trigger_timers(spies.ha_command, 5000) {
    Error(_) -> Error(Nil)
    Ok(count) -> {
      // Keep waiting for more timers with shorter timeout
      // TRV and heating paths run in parallel, so more timers may arrive
      Ok(count + wait_and_immediately_trigger_loop(spies.ha_command, 200))
    }
  }
}

/// Loop waiting for additional timers, IMMEDIATELY triggering each one.
/// Returns when no more timers arrive within timeout_ms.
fn wait_and_immediately_trigger_loop(
  spy: Subject(timer.TimerRequest(msg)),
  timeout_ms: Int,
) -> Int {
  case process.receive(spy, timeout_ms) {
    Ok(timer.TimerRequest(subject, _delay, msg)) -> {
      process.send(subject, msg)
      1 + wait_and_immediately_trigger_loop(spy, timeout_ms)
    }
    Error(_) -> 0
  }
}

// =============================================================================
// Polling helpers - wait for observable outcomes instead of arbitrary sleeps
// =============================================================================

/// Wait until fake_ha records a heating command with the expected mode, or timeout.
/// This is the proper way to synchronize - wait for observable behavior.
fn wait_for_heating_command(
  fake_ha: fake_ha_server.Server,
  expected_mode: mode.HvacMode,
  timeout_ms: Int,
) -> Result(List(#(entity_id.ClimateEntityId, mode.HvacMode)), Nil) {
  wait_for_heating_command_loop(fake_ha, expected_mode, timeout_ms, 50)
}

fn wait_for_heating_command_loop(
  fake_ha: fake_ha_server.Server,
  expected_mode: mode.HvacMode,
  remaining_ms: Int,
  poll_interval_ms: Int,
) -> Result(List(#(entity_id.ClimateEntityId, mode.HvacMode)), Nil) {
  case remaining_ms <= 0 {
    True -> Error(Nil)
    // Timeout
    False -> {
      let calls = fake_ha_server.get_set_hvac_mode_calls(fake_ha)
      case has_heating_command(calls, expected_mode) {
        True -> Ok(calls)
        False -> {
          process.sleep(poll_interval_ms)
          wait_for_heating_command_loop(
            fake_ha,
            expected_mode,
            remaining_ms - poll_interval_ms,
            poll_interval_ms,
          )
        }
      }
    }
  }
}

/// Check if the calls list contains a heating command with the expected mode
fn has_heating_command(
  calls: List(#(entity_id.ClimateEntityId, mode.HvacMode)),
  expected_mode: mode.HvacMode,
) -> Bool {
  let assert Ok(heating_id) =
    entity_id.climate_entity_id("climate.main_heating")
  list.any(calls, fn(call) { call.0 == heating_id && call.1 == expected_mode })
}

/// Wait until house mode matches the expected mode, or timeout.
fn wait_for_house_mode(
  system: supervisor.SupervisorWithRooms,
  expected_mode: mode.HouseMode,
  timeout_ms: Int,
) -> Result(mode.HouseMode, Nil) {
  wait_for_house_mode_loop(system, expected_mode, timeout_ms, 50)
}

fn wait_for_house_mode_loop(
  system: supervisor.SupervisorWithRooms,
  expected_mode: mode.HouseMode,
  remaining_ms: Int,
  poll_interval_ms: Int,
) -> Result(mode.HouseMode, Nil) {
  case remaining_ms <= 0 {
    True -> Error(Nil)
    // Timeout
    False -> {
      let current_mode = supervisor.get_current_house_mode(system)
      case current_mode == expected_mode {
        True -> Ok(current_mode)
        False -> {
          process.sleep(poll_interval_ms)
          wait_for_house_mode_loop(
            system,
            expected_mode,
            remaining_ms - poll_interval_ms,
            poll_interval_ms,
          )
        }
      }
    }
  }
}

/// Wait until UI subscriber receives a state with the expected number of rooms.
/// Repeatedly flushes the state aggregator timer to trigger broadcasts.
fn wait_for_ui_state_with_rooms(
  ui_subscriber: Subject(DeepHeatingState),
  state_aggregator_spy: Subject(
    timer.TimerRequest(state_aggregator_actor.Message),
  ),
  expected_room_count: Int,
  timeout_ms: Int,
) -> Result(DeepHeatingState, Nil) {
  wait_for_ui_state_loop(
    ui_subscriber,
    state_aggregator_spy,
    expected_room_count,
    timeout_ms,
    100,
  )
}

fn wait_for_ui_state_loop(
  ui_subscriber: Subject(DeepHeatingState),
  state_aggregator_spy: Subject(
    timer.TimerRequest(state_aggregator_actor.Message),
  ),
  expected_room_count: Int,
  remaining_ms: Int,
  poll_interval_ms: Int,
) -> Result(DeepHeatingState, Nil) {
  case remaining_ms <= 0 {
    True -> Error(Nil)
    False -> {
      // Flush any pending timer requests to trigger broadcast
      let _ = flush_timer_spy(state_aggregator_spy)
      // Try to receive state with short timeout
      case process.receive(ui_subscriber, poll_interval_ms) {
        Ok(received_state) -> {
          case list.length(received_state.rooms) >= expected_room_count {
            True -> Ok(received_state)
            False -> {
              // Got state but not enough rooms yet
              wait_for_ui_state_loop(
                ui_subscriber,
                state_aggregator_spy,
                expected_room_count,
                remaining_ms - poll_interval_ms,
                poll_interval_ms,
              )
            }
          }
        }
        Error(_) -> {
          // No state yet, keep trying
          wait_for_ui_state_loop(
            ui_subscriber,
            state_aggregator_spy,
            expected_room_count,
            remaining_ms - poll_interval_ms,
            poll_interval_ms,
          )
        }
      }
    }
  }
}

// =============================================================================
// The main e2e test
// =============================================================================

pub fn full_system_wiring_turns_on_heating_when_cold_test() {
  let port = base_port + 1

  // 1. Start fake HA with cold rooms (below schedule target)
  let assert Ok(fake_ha) = start_fake_ha_with_cold_rooms(port)

  // Give the server time to be ready for connections
  // Mist needs more time to fully bind to the port
  process.sleep(500)

  // 2. Start Deep Heating supervisor pointing at fake HA
  let assert Ok(TestSystem(supervisor: system, spies: spies)) =
    start_deep_heating(port)

  // 3. Trigger a poll to get initial state
  trigger_poll(system)

  // 4. Wait for the message chain to complete and ALL timers to be scheduled,
  //    then trigger them. HaCommandActor handles both TRV and heating commands
  //    through the same spy, so we need to trigger all of them.
  let assert Ok(_) = wait_and_immediately_trigger_ha_command_timers(spies)

  // 5. Wait for observable outcome - the heating command arriving at fake HA
  //    This replaces arbitrary process.sleep(100) with proper synchronization
  let assert Ok(_) = wait_for_heating_command(fake_ha, mode.HvacHeat, 5000)

  // Cleanup
  supervisor.shutdown_with_rooms(system)
  fake_ha_server.stop(fake_ha)
}

pub fn full_system_wiring_turns_off_heating_when_warm_test() {
  let port = base_port + 2

  // 1. Start fake HA with warm rooms (at or above schedule target)
  let assert Ok(fake_ha) = start_fake_ha_with_warm_rooms(port)

  // Give the server time to be ready for connections
  // Mist needs more time to fully bind to the port
  process.sleep(500)

  // 2. Start Deep Heating supervisor
  let assert Ok(TestSystem(supervisor: system, spies: spies)) =
    start_deep_heating(port)

  // 3. Trigger poll and wait for ALL timers to be scheduled
  trigger_poll(system)
  let assert Ok(_) = wait_and_immediately_trigger_ha_command_timers(spies)

  // 4. Wait for observable outcome - the heating OFF command arriving at fake HA
  let assert Ok(_) = wait_for_heating_command(fake_ha, mode.HvacOff, 5000)

  // Cleanup
  supervisor.shutdown_with_rooms(system)
  fake_ha_server.stop(fake_ha)
}

/// Test that sleep button press correctly changes house mode.
/// This test was previously flaky (dh-33jq.65.1) but now uses controlled timers.
pub fn full_system_wiring_responds_to_sleep_button_test() {
  let port = base_port + 3

  // 1. Start fake HA with cold rooms and sleep button not pressed
  let assert Ok(fake_ha) = start_fake_ha_with_cold_rooms(port)

  // Give the server time to be ready for connections
  // Mist needs more time to fully bind to the port
  process.sleep(500)

  // 2. Start Deep Heating supervisor with evening time (after 8pm for sleep button to work)
  let evening_time = fn() {
    house_mode_actor.local_datetime(2026, 1, 5, 22, 30, 0)
  }
  let assert Ok(TestSystem(supervisor: system, spies: _spies)) =
    start_deep_heating_with_time_provider(port, Some(evening_time))

  // 3. Initial poll to establish baseline state
  //    (need short wait for HTTP to complete - can't poll for this since mode doesn't change)
  trigger_poll(system)
  process.sleep(200)

  // 4. Press the sleep button (update fake HA state)
  press_sleep_button(fake_ha)

  // 5. Trigger another poll to detect the button press
  trigger_poll(system)

  // 6. Wait for observable outcome - house mode changes to sleeping
  //    Event chain: poll → HTTP → parse → EventRouter → HouseModeActor
  let assert Ok(_) = wait_for_house_mode(system, mode.HouseModeSleeping, 5000)

  // Cleanup
  supervisor.shutdown_with_rooms(system)
  fake_ha_server.stop(fake_ha)
}

pub fn full_system_wiring_broadcasts_state_to_ui_subscribers_test() {
  let port = base_port + 4

  // 1. Start fake HA with cold rooms
  let assert Ok(fake_ha) = start_fake_ha_with_cold_rooms(port)

  // Give the server time to be ready for connections
  // Mist needs more time to fully bind to the port
  process.sleep(500)

  // 2. Start Deep Heating supervisor
  let assert Ok(TestSystem(supervisor: system, spies: spies)) =
    start_deep_heating(port)

  // 3. Subscribe a test subject to the StateAggregatorActor (simulates UI client)
  let ui_subscriber: Subject(DeepHeatingState) = process.new_subject()
  let state_aggregator = supervisor.get_state_aggregator_subject(system)
  process.send(
    state_aggregator,
    state_aggregator_actor.Subscribe(ui_subscriber),
  )

  // 4. Trigger a poll to get HA state
  trigger_poll(system)

  // 5. Wait for observable outcome - UI state with 1 room
  //    This polls and flushes state aggregator timer until we get expected state
  let assert Ok(received_state) =
    wait_for_ui_state_with_rooms(ui_subscriber, spies.state_aggregator, 1, 5000)

  // 6. Verify the received state
  list.length(received_state.rooms) |> should.equal(1)
  let assert Ok(lounge) =
    list.find(received_state.rooms, fn(r) { r.name == "lounge" })
  lounge.name |> should.equal("lounge")

  // Cleanup
  process.send(
    state_aggregator,
    state_aggregator_actor.Unsubscribe(ui_subscriber),
  )
  supervisor.shutdown_with_rooms(system)
  fake_ha_server.stop(fake_ha)
}

// =============================================================================
// Helper functions - these need to be implemented
// =============================================================================

/// Start a fake HA server with rooms in a cold state (below target temperature)
fn start_fake_ha_with_cold_rooms(
  port: Int,
) -> Result(fake_ha_server.Server, String) {
  // Start the fake server
  case fake_ha_server.start(port, test_token) {
    Error(e) -> Error(e)
    Ok(server) -> {
      // Configure TRV entity - cold (15°C current, 20°C target)
      let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")
      fake_ha_server.set_climate_entity(
        server,
        trv_id,
        ClimateEntityState(
          current_temperature: Some(temperature.temperature(15.0)),
          target_temperature: Some(temperature.temperature(20.0)),
          hvac_mode: mode.HvacHeat,
          hvac_action: Some("idle"),
        ),
      )

      // Configure external temperature sensor - also cold
      let assert Ok(sensor_id) =
        entity_id.sensor_entity_id("sensor.lounge_temperature")
      fake_ha_server.set_sensor_entity(
        server,
        sensor_id,
        SensorEntityState(
          temperature: Some(temperature.temperature(15.0)),
          is_available: True,
        ),
      )

      // Configure main heating entity - currently off
      let assert Ok(heating_id) =
        entity_id.climate_entity_id("climate.main_heating")
      fake_ha_server.set_climate_entity(
        server,
        heating_id,
        ClimateEntityState(
          current_temperature: None,
          target_temperature: Some(temperature.temperature(20.0)),
          hvac_mode: mode.HvacOff,
          hvac_action: None,
        ),
      )

      // Configure sleep button - not pressed recently
      fake_ha_server.set_input_button(
        server,
        "input_button.goodnight",
        "2020-01-01T00:00:00+00:00",
      )

      Ok(server)
    }
  }
}

/// Start a fake HA server with rooms at target temperature (warm)
fn start_fake_ha_with_warm_rooms(
  port: Int,
) -> Result(fake_ha_server.Server, String) {
  case fake_ha_server.start(port, test_token) {
    Error(e) -> Error(e)
    Ok(server) -> {
      // Configure TRV entity - warm (22°C current, 20°C target)
      let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")
      fake_ha_server.set_climate_entity(
        server,
        trv_id,
        ClimateEntityState(
          current_temperature: Some(temperature.temperature(22.0)),
          target_temperature: Some(temperature.temperature(20.0)),
          hvac_mode: mode.HvacHeat,
          hvac_action: Some("idle"),
        ),
      )

      // Configure external temperature sensor - warm
      let assert Ok(sensor_id) =
        entity_id.sensor_entity_id("sensor.lounge_temperature")
      fake_ha_server.set_sensor_entity(
        server,
        sensor_id,
        SensorEntityState(
          temperature: Some(temperature.temperature(22.0)),
          is_available: True,
        ),
      )

      // Configure main heating entity - already heating (to test turn-off path)
      let assert Ok(heating_id) =
        entity_id.climate_entity_id("climate.main_heating")
      fake_ha_server.set_climate_entity(
        server,
        heating_id,
        ClimateEntityState(
          current_temperature: None,
          target_temperature: Some(temperature.temperature(20.0)),
          hvac_mode: mode.HvacHeat,
          hvac_action: Some("heating"),
        ),
      )

      // Configure sleep button
      fake_ha_server.set_input_button(
        server,
        "input_button.goodnight",
        "2020-01-01T00:00:00+00:00",
      )

      Ok(server)
    }
  }
}

/// Start the Deep Heating supervisor pointing at the fake HA
fn start_deep_heating(
  port: Int,
) -> Result(TestSystem, supervisor.StartWithRoomsError) {
  start_deep_heating_with_options(port, None)
}

/// Start the Deep Heating supervisor with an optional time provider (for testing time-based logic)
fn start_deep_heating_with_time_provider(
  port: Int,
  time_provider: Option(house_mode_actor.TimeProvider),
) -> Result(TestSystem, supervisor.StartWithRoomsError) {
  start_deep_heating_with_options(port, time_provider)
}

/// Result of starting deep heating with test infrastructure
type TestSystem {
  TestSystem(supervisor: supervisor.SupervisorWithRooms, spies: TestSpies)
}

/// Start the Deep Heating supervisor with all options
fn start_deep_heating_with_options(
  port: Int,
  time_provider: Option(house_mode_actor.TimeProvider),
) -> Result(TestSystem, supervisor.StartWithRoomsError) {
  let ha_client =
    HaClient("http://127.0.0.1:" <> int_to_string(port), test_token)

  let home_config = make_test_home_config()
  let poller_config = make_poller_config(home_config)

  // Use port as a unique prefix for actor names to avoid conflicts in parallel tests
  let name_prefix = "e2e_" <> int_to_string(port)

  // Create spy subjects for all actors - gives complete control over timing
  let spies = create_test_spies()

  case
    supervisor.start_with_home_config(supervisor.SupervisorConfigWithRooms(
      ha_client: ha_client,
      poller_config: poller_config,
      adjustments_path: test_adjustments_path,
      home_config: home_config,
      name_prefix: Some(name_prefix),
      time_provider: time_provider,
      house_mode_deps: supervisor.HouseModeDeps(
        send_after: timer.spy_send_after(spies.house_mode),
      ),
      ha_poller_deps: supervisor.HaPollerDeps(send_after: timer.spy_send_after(
        spies.ha_poller,
      )),
      room_actor_deps: supervisor.RoomActorDeps(
        send_after: timer.spy_send_after(spies.room_actor),
      ),
      ha_command_deps: supervisor.HaCommandDeps(
        send_after: timer.spy_send_after(spies.ha_command),
        debounce_ms: 5000,
      ),
      // Use throttle_ms: 0 for immediate broadcasts - eliminates need to flush timer spy
      state_aggregator_deps: supervisor.StateAggregatorDeps(
        send_after: timer.spy_send_after(spies.state_aggregator),
        throttle_ms: 0,
      ),
    ))
  {
    Ok(started) -> Ok(TestSystem(supervisor: started.data, spies: spies))
    Error(e) -> Error(e)
  }
}

/// Trigger an immediate poll on the system
fn trigger_poll(system: supervisor.SupervisorWithRooms) -> Nil {
  let poller_subject = supervisor.get_ha_poller_subject(system)
  process.send(poller_subject, ha_poller_actor.PollNow)
}

/// Press the sleep button in fake HA
fn press_sleep_button(server: fake_ha_server.Server) -> Nil {
  // Update the sleep button timestamp to "now"
  fake_ha_server.set_input_button(
    server,
    "input_button.goodnight",
    "2026-01-05T22:30:00+00:00",
  )
}

// =============================================================================
// Multi-room integration test
// =============================================================================

/// Tests that heating demand is correctly aggregated across multiple rooms.
/// When one room is warm and one is cold, the boiler should stay ON.
pub fn full_system_wiring_multi_room_demand_aggregation_test() {
  let port = base_port + 5

  // 1. Start fake HA with two rooms: lounge (cold) and bedroom (warm)
  let assert Ok(fake_ha) = start_fake_ha_with_mixed_rooms(port)

  // Give the server time to be ready for connections
  process.sleep(500)

  // 2. Start Deep Heating supervisor with multi-room config
  let assert Ok(TestSystem(supervisor: system, spies: spies)) =
    start_deep_heating_multi_room(port)

  // 3. Trigger poll and wait for ALL timers to be scheduled
  trigger_poll(system)
  let assert Ok(_) = wait_and_immediately_trigger_ha_command_timers(spies)

  // 4. Wait for observable outcome - heating command arriving at fake HA
  //    Even though bedroom is warm, lounge is cold so heating should be ON
  let assert Ok(_) = wait_for_heating_command(fake_ha, mode.HvacHeat, 5000)

  // Cleanup
  supervisor.shutdown_with_rooms(system)
  fake_ha_server.stop(fake_ha)
}

/// Tests that UI state contains data for all rooms
pub fn full_system_wiring_multi_room_broadcasts_all_rooms_to_ui_test() {
  let port = base_port + 6

  // 1. Start fake HA with two rooms
  let assert Ok(fake_ha) = start_fake_ha_with_mixed_rooms(port)

  process.sleep(500)

  // 2. Start Deep Heating supervisor with multi-room config
  let assert Ok(TestSystem(supervisor: system, spies: spies)) =
    start_deep_heating_multi_room(port)

  // 3. Subscribe a test subject to the StateAggregatorActor (simulates UI client)
  let ui_subscriber: Subject(DeepHeatingState) = process.new_subject()
  let state_aggregator = supervisor.get_state_aggregator_subject(system)
  process.send(
    state_aggregator,
    state_aggregator_actor.Subscribe(ui_subscriber),
  )

  // 4. Trigger a poll to get HA state
  trigger_poll(system)

  // 5. Wait for observable outcome - UI state with 2 rooms
  let assert Ok(received_state) =
    wait_for_ui_state_with_rooms(ui_subscriber, spies.state_aggregator, 2, 5000)

  // 6. Verify both rooms are present
  list.length(received_state.rooms) |> should.equal(2)
  let room_names =
    received_state.rooms
    |> list.map(fn(r) { r.name })
    |> set.from_list
  set.contains(room_names, "lounge") |> should.be_true
  set.contains(room_names, "bedroom") |> should.be_true

  // Cleanup
  process.send(
    state_aggregator,
    state_aggregator_actor.Unsubscribe(ui_subscriber),
  )
  supervisor.shutdown_with_rooms(system)
  fake_ha_server.stop(fake_ha)
}

// =============================================================================
// Test configuration helpers
// =============================================================================

fn make_test_home_config() -> HomeConfig {
  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")
  let assert Ok(sensor_id) =
    entity_id.sensor_entity_id("sensor.lounge_temperature")
  let assert Ok(sleep_switch) =
    entity_id.goodnight_entity_id("input_button.goodnight")
  let assert Ok(heating_id) =
    entity_id.climate_entity_id("climate.main_heating")

  HomeConfig(
    rooms: [
      RoomConfig(
        name: "lounge",
        temperature_sensor_entity_id: Some(sensor_id),
        climate_entity_ids: [trv_id],
        schedule: Some(make_all_day_schedule(20.0)),
      ),
    ],
    sleep_switch_id: sleep_switch,
    heating_id: heating_id,
  )
}

fn make_poller_config(home_config: HomeConfig) -> ha_poller_actor.PollerConfig {
  // Build sets of managed entity IDs from the home config
  let trv_ids =
    home_config.rooms
    |> list.flat_map(fn(room) { room.climate_entity_ids })
    |> set.from_list

  let sensor_ids =
    home_config.rooms
    |> list.filter_map(fn(room) {
      case room.temperature_sensor_entity_id {
        Some(id) -> Ok(id)
        None -> Error(Nil)
      }
    })
    |> set.from_list

  ha_poller_actor.PollerConfig(
    poll_interval_ms: 60_000,
    // Long interval - we'll trigger manually
    heating_entity_id: home_config.heating_id,
    sleep_button_entity_id: entity_id.goodnight_entity_id_to_string(
      home_config.sleep_switch_id,
    ),
    managed_trv_ids: trv_ids,
    managed_sensor_ids: sensor_ids,
  )
}

fn make_all_day_schedule(target: Float) -> schedule.WeekSchedule {
  let assert Ok(time) = schedule.time_of_day(0, 0)
  let entry =
    schedule.ScheduleEntry(
      start: time,
      target_temperature: temperature.temperature(target),
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

fn int_to_string(n: Int) -> String {
  case n {
    _ if n < 0 -> "-" <> int_to_string(-n)
    0 -> "0"
    1 -> "1"
    2 -> "2"
    3 -> "3"
    4 -> "4"
    5 -> "5"
    6 -> "6"
    7 -> "7"
    8 -> "8"
    9 -> "9"
    _ -> int_to_string(n / 10) <> int_to_string(n % 10)
  }
}

// =============================================================================
// Multi-room test helpers
// =============================================================================

/// Start a fake HA server with two rooms: lounge (cold) and bedroom (warm)
fn start_fake_ha_with_mixed_rooms(
  port: Int,
) -> Result(fake_ha_server.Server, String) {
  case fake_ha_server.start(port, test_token) {
    Error(e) -> Error(e)
    Ok(server) -> {
      // Configure lounge TRV - cold (15°C current, 20°C target) - needs heating
      let assert Ok(lounge_trv_id) =
        entity_id.climate_entity_id("climate.lounge_trv")
      fake_ha_server.set_climate_entity(
        server,
        lounge_trv_id,
        ClimateEntityState(
          current_temperature: Some(temperature.temperature(15.0)),
          target_temperature: Some(temperature.temperature(20.0)),
          hvac_mode: mode.HvacHeat,
          hvac_action: Some("idle"),
        ),
      )

      // Configure lounge external temperature sensor - cold
      let assert Ok(lounge_sensor_id) =
        entity_id.sensor_entity_id("sensor.lounge_temperature")
      fake_ha_server.set_sensor_entity(
        server,
        lounge_sensor_id,
        SensorEntityState(
          temperature: Some(temperature.temperature(15.0)),
          is_available: True,
        ),
      )

      // Configure bedroom TRV - warm (22°C current, 20°C target) - doesn't need heating
      let assert Ok(bedroom_trv_id) =
        entity_id.climate_entity_id("climate.bedroom_trv")
      fake_ha_server.set_climate_entity(
        server,
        bedroom_trv_id,
        ClimateEntityState(
          current_temperature: Some(temperature.temperature(22.0)),
          target_temperature: Some(temperature.temperature(20.0)),
          hvac_mode: mode.HvacHeat,
          hvac_action: Some("idle"),
        ),
      )

      // Configure bedroom external temperature sensor - warm
      let assert Ok(bedroom_sensor_id) =
        entity_id.sensor_entity_id("sensor.bedroom_temperature")
      fake_ha_server.set_sensor_entity(
        server,
        bedroom_sensor_id,
        SensorEntityState(
          temperature: Some(temperature.temperature(22.0)),
          is_available: True,
        ),
      )

      // Configure main heating entity - currently off
      let assert Ok(heating_id) =
        entity_id.climate_entity_id("climate.main_heating")
      fake_ha_server.set_climate_entity(
        server,
        heating_id,
        ClimateEntityState(
          current_temperature: None,
          target_temperature: Some(temperature.temperature(20.0)),
          hvac_mode: mode.HvacOff,
          hvac_action: None,
        ),
      )

      // Configure sleep button - not pressed recently
      fake_ha_server.set_input_button(
        server,
        "input_button.goodnight",
        "2020-01-01T00:00:00+00:00",
      )

      Ok(server)
    }
  }
}

/// Create a multi-room home config with lounge and bedroom
fn make_multi_room_home_config() -> HomeConfig {
  let assert Ok(lounge_trv_id) =
    entity_id.climate_entity_id("climate.lounge_trv")
  let assert Ok(lounge_sensor_id) =
    entity_id.sensor_entity_id("sensor.lounge_temperature")
  let assert Ok(bedroom_trv_id) =
    entity_id.climate_entity_id("climate.bedroom_trv")
  let assert Ok(bedroom_sensor_id) =
    entity_id.sensor_entity_id("sensor.bedroom_temperature")
  let assert Ok(sleep_switch) =
    entity_id.goodnight_entity_id("input_button.goodnight")
  let assert Ok(heating_id) =
    entity_id.climate_entity_id("climate.main_heating")

  HomeConfig(
    rooms: [
      RoomConfig(
        name: "lounge",
        temperature_sensor_entity_id: Some(lounge_sensor_id),
        climate_entity_ids: [lounge_trv_id],
        schedule: Some(make_all_day_schedule(20.0)),
      ),
      RoomConfig(
        name: "bedroom",
        temperature_sensor_entity_id: Some(bedroom_sensor_id),
        climate_entity_ids: [bedroom_trv_id],
        schedule: Some(make_all_day_schedule(20.0)),
      ),
    ],
    sleep_switch_id: sleep_switch,
    heating_id: heating_id,
  )
}

/// Start the Deep Heating supervisor with multi-room config
fn start_deep_heating_multi_room(
  port: Int,
) -> Result(TestSystem, supervisor.StartWithRoomsError) {
  let ha_client =
    HaClient("http://127.0.0.1:" <> int_to_string(port), test_token)

  let home_config = make_multi_room_home_config()
  let poller_config = make_poller_config(home_config)

  // Use port as a unique prefix for actor names to avoid conflicts in parallel tests
  let name_prefix = "e2e_multi_" <> int_to_string(port)

  // Create spy subjects for all actors - gives complete control over timing
  let spies = create_test_spies()

  case
    supervisor.start_with_home_config(supervisor.SupervisorConfigWithRooms(
      ha_client: ha_client,
      poller_config: poller_config,
      adjustments_path: test_adjustments_path,
      home_config: home_config,
      name_prefix: Some(name_prefix),
      time_provider: None,
      house_mode_deps: supervisor.HouseModeDeps(
        send_after: timer.spy_send_after(spies.house_mode),
      ),
      ha_poller_deps: supervisor.HaPollerDeps(send_after: timer.spy_send_after(
        spies.ha_poller,
      )),
      room_actor_deps: supervisor.RoomActorDeps(
        send_after: timer.spy_send_after(spies.room_actor),
      ),
      ha_command_deps: supervisor.HaCommandDeps(
        send_after: timer.spy_send_after(spies.ha_command),
        debounce_ms: 5000,
      ),
      // Use throttle_ms: 0 for immediate broadcasts - eliminates need to flush timer spy
      state_aggregator_deps: supervisor.StateAggregatorDeps(
        send_after: timer.spy_send_after(spies.state_aggregator),
        throttle_ms: 0,
      ),
    ))
  {
    Ok(started) -> Ok(TestSystem(supervisor: started.data, spies: spies))
    Error(e) -> Error(e)
  }
}

// =============================================================================
// Zero debounce tests - commands fire immediately without timer spy
// =============================================================================

/// Test that commands fire immediately when debounce_ms is set to 0.
/// This allows tests to work without needing to manually trigger ha_command timers.
pub fn commands_fire_immediately_with_zero_debounce_test() {
  let port = base_port + 7

  // 1. Start fake HA with cold rooms
  let assert Ok(fake_ha) = start_fake_ha_with_cold_rooms(port)
  process.sleep(500)

  // 2. Start Deep Heating with debounce_ms: 0 - no timer spy needed!
  let assert Ok(TestSystem(supervisor: system, spies: _spies)) =
    start_deep_heating_with_zero_debounce(port)

  // 3. Trigger a poll to get initial state
  trigger_poll(system)

  // 4. Wait for observable outcome WITHOUT triggering ha_command timers!
  //    With debounce_ms: 0, commands should fire immediately.
  let assert Ok(_) = wait_for_heating_command(fake_ha, mode.HvacHeat, 5000)

  // Cleanup
  supervisor.shutdown_with_rooms(system)
  fake_ha_server.stop(fake_ha)
}

/// Start Deep Heating with zero debounce - commands fire immediately
fn start_deep_heating_with_zero_debounce(
  port: Int,
) -> Result(TestSystem, supervisor.StartWithRoomsError) {
  let ha_client =
    HaClient("http://127.0.0.1:" <> int_to_string(port), test_token)

  let home_config = make_test_home_config()
  let poller_config = make_poller_config(home_config)
  let name_prefix = "e2e_zero_debounce_" <> int_to_string(port)
  let spies = create_test_spies()

  case
    supervisor.start_with_home_config(supervisor.SupervisorConfigWithRooms(
      ha_client: ha_client,
      poller_config: poller_config,
      adjustments_path: test_adjustments_path,
      home_config: home_config,
      name_prefix: Some(name_prefix),
      time_provider: None,
      house_mode_deps: supervisor.HouseModeDeps(
        send_after: timer.spy_send_after(spies.house_mode),
      ),
      ha_poller_deps: supervisor.HaPollerDeps(send_after: timer.spy_send_after(
        spies.ha_poller,
      )),
      room_actor_deps: supervisor.RoomActorDeps(
        send_after: timer.spy_send_after(spies.room_actor),
      ),
      // This is the key change - add debounce_ms: 0 to eliminate timer dependency
      ha_command_deps: supervisor.HaCommandDeps(
        send_after: timer.real_send_after,
        debounce_ms: 0,
      ),
      // Also use throttle_ms: 0 for immediate broadcasts
      state_aggregator_deps: supervisor.StateAggregatorDeps(
        send_after: timer.spy_send_after(spies.state_aggregator),
        throttle_ms: 0,
      ),
    ))
  {
    Ok(started) -> Ok(TestSystem(supervisor: started.data, spies: spies))
    Error(e) -> Error(e)
  }
}
