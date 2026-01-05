//// Tests for the fake Home Assistant HTTP server used in e2e testing.

import deep_heating/entity_id
import deep_heating/home_assistant/client.{HaClient}
import deep_heating/mode
import deep_heating/temperature
import fake_ha_server
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should

// -----------------------------------------------------------------------------
// Server lifecycle tests
// -----------------------------------------------------------------------------

pub fn starts_on_specified_port_test() {
  let port = 9100

  let assert Ok(server) = fake_ha_server.start(port, "test-token")

  // Server should be running - we'll verify by making a request
  let client =
    HaClient("http://localhost:" <> port_to_string(port), "test-token")
  let result = client.get_states(client)

  // Should succeed (empty array is valid)
  result |> should.be_ok

  fake_ha_server.stop(server)
}

pub fn stop_returns_without_error_test() {
  let port = 9101

  let assert Ok(server) = fake_ha_server.start(port, "test-token")

  // Stop should return without crashing
  // Note: mist servers run until the BEAM process exits, so we can't verify
  // the server is actually unreachable. Each test uses a unique port for isolation.
  fake_ha_server.stop(server)
}

// -----------------------------------------------------------------------------
// Authorization tests
// -----------------------------------------------------------------------------

pub fn rejects_request_without_auth_header_test() {
  let port = 9102

  let assert Ok(server) = fake_ha_server.start(port, "valid-token")

  // Use wrong token
  let client =
    HaClient("http://localhost:" <> port_to_string(port), "wrong-token")
  let result = client.get_states(client)

  result |> should.equal(Error(client.AuthenticationError))

  fake_ha_server.stop(server)
}

pub fn accepts_request_with_valid_token_test() {
  let port = 9103

  let assert Ok(server) = fake_ha_server.start(port, "my-secret-token")

  let client =
    HaClient("http://localhost:" <> port_to_string(port), "my-secret-token")
  let result = client.get_states(client)

  result |> should.be_ok

  fake_ha_server.stop(server)
}

// -----------------------------------------------------------------------------
// GET /api/states tests
// -----------------------------------------------------------------------------

pub fn get_states_returns_empty_array_by_default_test() {
  let port = 9104

  let assert Ok(server) = fake_ha_server.start(port, "token")

  let client = HaClient("http://localhost:" <> port_to_string(port), "token")
  let assert Ok(json) = client.get_states(client)

  json |> should.equal("[]")

  fake_ha_server.stop(server)
}

pub fn get_states_returns_configured_climate_entities_test() {
  let port = 9105

  let assert Ok(server) = fake_ha_server.start(port, "token")

  // Set up a climate entity
  let assert Ok(entity_id) = entity_id.climate_entity_id("climate.lounge_trv")
  fake_ha_server.set_climate_entity(
    server,
    entity_id,
    fake_ha_server.ClimateEntityState(
      current_temperature: Some(temperature.temperature(20.5)),
      target_temperature: Some(temperature.temperature(21.0)),
      hvac_mode: mode.HvacHeat,
      hvac_action: Some("heating"),
    ),
  )

  let client = HaClient("http://localhost:" <> port_to_string(port), "token")
  let assert Ok(json) = client.get_states(client)

  // Parse the JSON to verify
  let assert Ok(entities) = client.parse_climate_entities(json)
  let assert [entity] = entities

  entity.entity_id |> should.equal(entity_id)
  entity.current_temperature
  |> should.equal(Some(temperature.temperature(20.5)))
  entity.target_temperature |> should.equal(Some(temperature.temperature(21.0)))
  entity.hvac_mode |> should.equal(mode.HvacHeat)
  entity.is_heating |> should.be_true

  fake_ha_server.stop(server)
}

pub fn get_states_returns_configured_sensor_entities_test() {
  let port = 9106

  let assert Ok(server) = fake_ha_server.start(port, "token")

  // Set up a sensor entity
  let assert Ok(entity_id) =
    entity_id.sensor_entity_id("sensor.lounge_temperature")
  fake_ha_server.set_sensor_entity(
    server,
    entity_id,
    fake_ha_server.SensorEntityState(
      temperature: Some(temperature.temperature(19.5)),
      is_available: True,
    ),
  )

  let client = HaClient("http://localhost:" <> port_to_string(port), "token")
  let assert Ok(json) = client.get_states(client)

  // Parse the JSON to verify
  let assert Ok(sensors) = client.parse_sensor_entities(json)
  let assert [sensor] = sensors

  sensor.entity_id |> should.equal(entity_id)
  sensor.temperature |> should.equal(Some(temperature.temperature(19.5)))
  sensor.is_available |> should.be_true

  fake_ha_server.stop(server)
}

pub fn get_states_returns_configured_input_button_test() {
  let port = 9107

  let assert Ok(server) = fake_ha_server.start(port, "token")

  fake_ha_server.set_input_button(
    server,
    "input_button.goodnight",
    "2026-01-03T22:30:00+00:00",
  )

  let client = HaClient("http://localhost:" <> port_to_string(port), "token")
  let assert Ok(json) = client.get_states(client)

  // Find the input_button state
  let assert Ok(state) =
    client.find_input_button_state(json, "input_button.goodnight")

  state |> should.equal("2026-01-03T22:30:00+00:00")

  fake_ha_server.stop(server)
}

// -----------------------------------------------------------------------------
// POST /api/services/climate/set_temperature tests
// -----------------------------------------------------------------------------

pub fn set_temperature_records_call_test() {
  let port = 9108

  let assert Ok(server) = fake_ha_server.start(port, "token")

  let client = HaClient("http://localhost:" <> port_to_string(port), "token")
  let assert Ok(entity_id) = entity_id.climate_entity_id("climate.bedroom_trv")
  let temp = temperature.temperature(22.0)

  let result = client.set_temperature(client, entity_id, temp)

  result |> should.be_ok

  // Verify the call was recorded
  let calls = fake_ha_server.get_set_temperature_calls(server)
  calls |> should.equal([#(entity_id, temp)])

  fake_ha_server.stop(server)
}

pub fn set_temperature_records_multiple_calls_test() {
  let port = 9109

  let assert Ok(server) = fake_ha_server.start(port, "token")

  let client = HaClient("http://localhost:" <> port_to_string(port), "token")
  let assert Ok(eid1) = entity_id.climate_entity_id("climate.bedroom_trv")
  let assert Ok(eid2) = entity_id.climate_entity_id("climate.lounge_trv")
  let temp1 = temperature.temperature(20.0)
  let temp2 = temperature.temperature(21.5)

  let _ = client.set_temperature(client, eid1, temp1)
  let _ = client.set_temperature(client, eid2, temp2)

  let calls = fake_ha_server.get_set_temperature_calls(server)
  list.length(calls) |> should.equal(2)

  fake_ha_server.stop(server)
}

// -----------------------------------------------------------------------------
// POST /api/services/climate/set_hvac_mode tests
// -----------------------------------------------------------------------------

pub fn set_hvac_mode_records_call_test() {
  let port = 9110

  let assert Ok(server) = fake_ha_server.start(port, "token")

  let client = HaClient("http://localhost:" <> port_to_string(port), "token")
  let assert Ok(entity_id) = entity_id.climate_entity_id("climate.kitchen_trv")

  let result = client.set_hvac_mode(client, entity_id, mode.HvacHeat)

  result |> should.be_ok

  // Verify the call was recorded
  let calls = fake_ha_server.get_set_hvac_mode_calls(server)
  calls |> should.equal([#(entity_id, mode.HvacHeat)])

  fake_ha_server.stop(server)
}

// -----------------------------------------------------------------------------
// State mutation tests
// -----------------------------------------------------------------------------

pub fn clear_calls_resets_recorded_calls_test() {
  let port = 9111

  let assert Ok(server) = fake_ha_server.start(port, "token")

  let client = HaClient("http://localhost:" <> port_to_string(port), "token")
  let assert Ok(entity_id) = entity_id.climate_entity_id("climate.office_trv")
  let temp = temperature.temperature(19.0)

  let _ = client.set_temperature(client, entity_id, temp)

  // Verify there are calls
  fake_ha_server.get_set_temperature_calls(server)
  |> list.length
  |> should.equal(1)

  // Clear and verify
  fake_ha_server.clear_calls(server)

  fake_ha_server.get_set_temperature_calls(server) |> should.equal([])
  fake_ha_server.get_set_hvac_mode_calls(server) |> should.equal([])

  fake_ha_server.stop(server)
}

pub fn update_climate_entity_changes_state_test() {
  let port = 9112

  let assert Ok(server) = fake_ha_server.start(port, "token")

  let assert Ok(entity_id) = entity_id.climate_entity_id("climate.hallway_trv")

  // Set initial state
  fake_ha_server.set_climate_entity(
    server,
    entity_id,
    fake_ha_server.ClimateEntityState(
      current_temperature: Some(temperature.temperature(18.0)),
      target_temperature: Some(temperature.temperature(19.0)),
      hvac_mode: mode.HvacOff,
      hvac_action: None,
    ),
  )

  // Update to new state
  fake_ha_server.set_climate_entity(
    server,
    entity_id,
    fake_ha_server.ClimateEntityState(
      current_temperature: Some(temperature.temperature(19.0)),
      target_temperature: Some(temperature.temperature(21.0)),
      hvac_mode: mode.HvacHeat,
      hvac_action: Some("heating"),
    ),
  )

  let client = HaClient("http://localhost:" <> port_to_string(port), "token")
  let assert Ok(json) = client.get_states(client)
  let assert Ok([entity]) = client.parse_climate_entities(json)

  entity.current_temperature
  |> should.equal(Some(temperature.temperature(19.0)))
  entity.target_temperature |> should.equal(Some(temperature.temperature(21.0)))
  entity.hvac_mode |> should.equal(mode.HvacHeat)

  fake_ha_server.stop(server)
}

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

fn port_to_string(port: Int) -> String {
  int.to_string(port)
}
