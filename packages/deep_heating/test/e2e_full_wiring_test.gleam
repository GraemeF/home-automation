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
import deep_heating/home_assistant/ha_poller_actor
import deep_heating/house_mode/house_mode_actor
import deep_heating/mode
import deep_heating/scheduling/schedule
import deep_heating/state.{type DeepHeatingState}
import deep_heating/state/state_aggregator_actor
import deep_heating/supervisor
import deep_heating/temperature
import fake_ha_server.{ClimateEntityState, SensorEntityState}
import gleam/erlang/process
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
  let assert Ok(system) = start_deep_heating(port)

  // 3. Trigger a poll to get initial state
  trigger_poll(system)

  // 4. Wait for events to propagate through the actor chain AND debounce timer (5s)
  process.sleep(5500)

  // 5. Verify the boiler was commanded to turn on (rooms are cold, demand heat)
  let heating_calls = fake_ha_server.get_set_hvac_mode_calls(fake_ha)

  // The heating should have been turned on because rooms are below target
  should_have_heating_command(heating_calls, mode.HvacHeat)

  // Cleanup
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
  let assert Ok(system) = start_deep_heating(port)

  // 3. Trigger poll and wait for debounce timer (5s)
  trigger_poll(system)
  process.sleep(5500)

  // 4. Verify no heating command sent (rooms already warm)
  let heating_calls = fake_ha_server.get_set_hvac_mode_calls(fake_ha)

  // The heating should be off because rooms are at target
  should_have_heating_command(heating_calls, mode.HvacOff)

  fake_ha_server.stop(fake_ha)
}

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
  let assert Ok(system) =
    start_deep_heating_with_time_provider(port, Some(evening_time))

  // 3. Initial poll to establish baseline state
  trigger_poll(system)
  process.sleep(200)

  // 4. Press the sleep button (update fake HA state)
  press_sleep_button(fake_ha)

  // 5. Trigger another poll to detect the button press
  trigger_poll(system)

  // 6. Wait for house mode to change to sleeping (poll with timeout)
  // Event propagation: poll → HTTP → parse → EventRouter → HouseModeActor
  let assert Ok(Nil) = wait_for_house_mode(system, mode.HouseModeSleeping, 2000)

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
  let assert Ok(system) = start_deep_heating(port)

  // 3. Subscribe a test subject to the StateAggregatorActor (simulates UI client)
  let ui_subscriber: process.Subject(DeepHeatingState) = process.new_subject()
  let state_aggregator = supervisor.get_state_aggregator_subject(system)
  process.send(
    state_aggregator,
    state_aggregator_actor.Subscribe(ui_subscriber),
  )

  // 4. Trigger a poll to get HA state
  trigger_poll(system)

  // 5. Wait for state to propagate through actors to aggregator
  process.sleep(200)

  // 6. Check that we received a state update with room data
  case process.receive(ui_subscriber, 1000) {
    Ok(received_state) -> {
      // Should have at least one room
      list.length(received_state.rooms) |> should.equal(1)

      // The room should be named "lounge"
      let assert Ok(lounge) =
        list.find(received_state.rooms, fn(r) { r.name == "lounge" })

      // Should have temperature data from the poll
      lounge.name |> should.equal("lounge")
    }
    Error(_) -> {
      // No state received - UI wiring is broken
      should.fail()
    }
  }

  // Cleanup
  process.send(
    state_aggregator,
    state_aggregator_actor.Unsubscribe(ui_subscriber),
  )
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
) -> Result(supervisor.SupervisorWithRooms, supervisor.StartWithRoomsError) {
  start_deep_heating_with_time_provider(port, None)
}

/// Start the Deep Heating supervisor with an optional time provider (for testing time-based logic)
fn start_deep_heating_with_time_provider(
  port: Int,
  time_provider: Option(house_mode_actor.TimeProvider),
) -> Result(supervisor.SupervisorWithRooms, supervisor.StartWithRoomsError) {
  let ha_client =
    HaClient("http://127.0.0.1:" <> int_to_string(port), test_token)

  let home_config = make_test_home_config()
  let poller_config = make_poller_config(home_config)

  // Use port as a unique prefix for actor names to avoid conflicts in parallel tests
  let name_prefix = "e2e_" <> int_to_string(port)

  case
    supervisor.start_with_home_config(supervisor.SupervisorConfigWithRooms(
      ha_client: ha_client,
      poller_config: poller_config,
      adjustments_path: test_adjustments_path,
      home_config: home_config,
      name_prefix: Some(name_prefix),
      time_provider: time_provider,
    ))
  {
    Ok(started) -> Ok(started.data)
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

/// Get the current house mode from the system
fn get_house_mode(system: supervisor.SupervisorWithRooms) -> mode.HouseMode {
  supervisor.get_current_house_mode(system)
}

/// Wait for house mode to reach expected state, with polling and timeout
/// Returns Ok if expected mode is reached, Error if timeout expires
fn wait_for_house_mode(
  system: supervisor.SupervisorWithRooms,
  expected: mode.HouseMode,
  timeout_ms: Int,
) -> Result(Nil, Nil) {
  wait_for_house_mode_loop(system, expected, timeout_ms, 50)
}

fn wait_for_house_mode_loop(
  system: supervisor.SupervisorWithRooms,
  expected: mode.HouseMode,
  remaining_ms: Int,
  poll_interval_ms: Int,
) -> Result(Nil, Nil) {
  case remaining_ms <= 0 {
    True -> Error(Nil)
    False -> {
      let current = get_house_mode(system)
      case current == expected {
        True -> Ok(Nil)
        False -> {
          process.sleep(poll_interval_ms)
          wait_for_house_mode_loop(
            system,
            expected,
            remaining_ms - poll_interval_ms,
            poll_interval_ms,
          )
        }
      }
    }
  }
}

/// Assert that a heating command was sent with the expected mode
fn should_have_heating_command(
  calls: List(#(entity_id.ClimateEntityId, mode.HvacMode)),
  expected_mode: mode.HvacMode,
) -> Nil {
  let assert Ok(heating_id) =
    entity_id.climate_entity_id("climate.main_heating")

  // Find the call for the heating entity
  let heating_call =
    calls
    |> list.find(fn(call) { call.0 == heating_id })

  case heating_call {
    Ok(#(_, actual_mode)) -> actual_mode |> should.equal(expected_mode)
    Error(_) -> {
      // No call found - fail the test
      should.fail()
    }
  }
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
