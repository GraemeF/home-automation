import deep_heating/entity_id
import deep_heating/home_assistant.{HaClient}
import deep_heating/mode
import deep_heating/temperature
import envoy
import gleam/http
import gleam/http/request
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should

// -----------------------------------------------------------------------------
// build_get_states_request tests
// -----------------------------------------------------------------------------

pub fn build_get_states_request_uses_correct_url_test() {
  let client = HaClient("http://supervisor", "test-token-123")

  let req = home_assistant.build_get_states_request(client)

  req.host
  |> should.equal("supervisor")

  req.path
  |> should.equal("/api/states")
}

pub fn build_get_states_request_uses_get_method_test() {
  let client = HaClient("http://supervisor", "test-token-123")

  let req = home_assistant.build_get_states_request(client)

  req.method
  |> should.equal(http.Get)
}

pub fn build_get_states_request_includes_bearer_token_test() {
  let client = HaClient("http://supervisor", "my-secret-token")

  let req = home_assistant.build_get_states_request(client)

  request.get_header(req, "authorization")
  |> should.equal(Ok("Bearer my-secret-token"))
}

// -----------------------------------------------------------------------------
// build_set_temperature_request tests
// -----------------------------------------------------------------------------

pub fn build_set_temperature_request_uses_correct_url_test() {
  let client = HaClient("http://supervisor", "test-token")
  let assert Ok(entity_id) = entity_id.climate_entity_id("climate.living_room")
  let temp = temperature.temperature(21.5)

  let req =
    home_assistant.build_set_temperature_request(client, entity_id, temp)

  req.host
  |> should.equal("supervisor")

  req.path
  |> should.equal("/api/services/climate/set_temperature")
}

pub fn build_set_temperature_request_uses_post_method_test() {
  let client = HaClient("http://supervisor", "test-token")
  let assert Ok(entity_id) = entity_id.climate_entity_id("climate.bedroom")
  let temp = temperature.temperature(19.0)

  let req =
    home_assistant.build_set_temperature_request(client, entity_id, temp)

  req.method
  |> should.equal(http.Post)
}

pub fn build_set_temperature_request_includes_bearer_token_test() {
  let client = HaClient("http://supervisor", "secret-token")
  let assert Ok(entity_id) = entity_id.climate_entity_id("climate.kitchen")
  let temp = temperature.temperature(20.0)

  let req =
    home_assistant.build_set_temperature_request(client, entity_id, temp)

  request.get_header(req, "authorization")
  |> should.equal(Ok("Bearer secret-token"))
}

pub fn build_set_temperature_request_has_json_content_type_test() {
  let client = HaClient("http://supervisor", "test-token")
  let assert Ok(entity_id) = entity_id.climate_entity_id("climate.office")
  let temp = temperature.temperature(22.0)

  let req =
    home_assistant.build_set_temperature_request(client, entity_id, temp)

  request.get_header(req, "content-type")
  |> should.equal(Ok("application/json"))
}

pub fn build_set_temperature_request_has_correct_body_test() {
  let client = HaClient("http://supervisor", "test-token")
  let assert Ok(entity_id) = entity_id.climate_entity_id("climate.hallway")
  let temp = temperature.temperature(18.5)

  let req =
    home_assistant.build_set_temperature_request(client, entity_id, temp)

  // Body should be JSON with entity_id and temperature
  req.body
  |> should.equal("{\"entity_id\":\"climate.hallway\",\"temperature\":18.5}")
}

// -----------------------------------------------------------------------------
// build_set_hvac_mode_request tests
// -----------------------------------------------------------------------------

pub fn build_set_hvac_mode_request_uses_correct_url_test() {
  let client = HaClient("http://supervisor", "test-token")
  let assert Ok(eid) = entity_id.climate_entity_id("climate.living_room")

  let req =
    home_assistant.build_set_hvac_mode_request(client, eid, mode.HvacHeat)

  req.host
  |> should.equal("supervisor")

  req.path
  |> should.equal("/api/services/climate/set_hvac_mode")
}

pub fn build_set_hvac_mode_request_uses_post_method_test() {
  let client = HaClient("http://supervisor", "test-token")
  let assert Ok(eid) = entity_id.climate_entity_id("climate.bedroom")

  let req =
    home_assistant.build_set_hvac_mode_request(client, eid, mode.HvacAuto)

  req.method
  |> should.equal(http.Post)
}

pub fn build_set_hvac_mode_request_includes_bearer_token_test() {
  let client = HaClient("http://supervisor", "secret-token")
  let assert Ok(eid) = entity_id.climate_entity_id("climate.kitchen")

  let req =
    home_assistant.build_set_hvac_mode_request(client, eid, mode.HvacOff)

  request.get_header(req, "authorization")
  |> should.equal(Ok("Bearer secret-token"))
}

pub fn build_set_hvac_mode_request_has_json_content_type_test() {
  let client = HaClient("http://supervisor", "test-token")
  let assert Ok(eid) = entity_id.climate_entity_id("climate.office")

  let req =
    home_assistant.build_set_hvac_mode_request(client, eid, mode.HvacHeat)

  request.get_header(req, "content-type")
  |> should.equal(Ok("application/json"))
}

pub fn build_set_hvac_mode_request_body_for_heat_mode_test() {
  let client = HaClient("http://supervisor", "test-token")
  let assert Ok(eid) = entity_id.climate_entity_id("climate.hallway")

  let req =
    home_assistant.build_set_hvac_mode_request(client, eid, mode.HvacHeat)

  req.body
  |> should.equal("{\"entity_id\":\"climate.hallway\",\"hvac_mode\":\"heat\"}")
}

pub fn build_set_hvac_mode_request_body_for_off_mode_test() {
  let client = HaClient("http://supervisor", "test-token")
  let assert Ok(eid) = entity_id.climate_entity_id("climate.garage")

  let req =
    home_assistant.build_set_hvac_mode_request(client, eid, mode.HvacOff)

  req.body
  |> should.equal("{\"entity_id\":\"climate.garage\",\"hvac_mode\":\"off\"}")
}

pub fn build_set_hvac_mode_request_body_for_auto_mode_test() {
  let client = HaClient("http://supervisor", "test-token")
  let assert Ok(eid) = entity_id.climate_entity_id("climate.bathroom")

  let req =
    home_assistant.build_set_hvac_mode_request(client, eid, mode.HvacAuto)

  req.body
  |> should.equal("{\"entity_id\":\"climate.bathroom\",\"hvac_mode\":\"auto\"}")
}

// -----------------------------------------------------------------------------
// parse_climate_entities tests
// -----------------------------------------------------------------------------

pub fn parse_climate_entities_parses_single_climate_entity_test() {
  let json =
    "[{\"entity_id\":\"climate.lounge_trv\",\"state\":\"heat\",\"attributes\":{\"current_temperature\":20.5,\"temperature\":21.0,\"hvac_action\":\"heating\",\"friendly_name\":\"Lounge TRV\"}}]"

  let result = home_assistant.parse_climate_entities(json)

  let assert Ok(entities) = result
  let assert [entity] = entities

  let assert Ok(expected_id) = entity_id.climate_entity_id("climate.lounge_trv")
  entity.entity_id |> should.equal(expected_id)
  entity.current_temperature
  |> should.equal(Some(temperature.temperature(20.5)))
  entity.target_temperature |> should.equal(Some(temperature.temperature(21.0)))
  entity.hvac_mode |> should.equal(mode.HvacHeat)
  entity.is_heating |> should.be_true
}

pub fn parse_climate_entities_handles_off_mode_test() {
  let json =
    "[{\"entity_id\":\"climate.bedroom_trv\",\"state\":\"off\",\"attributes\":{\"current_temperature\":18.0,\"temperature\":15.0,\"hvac_action\":\"idle\",\"friendly_name\":\"Bedroom TRV\"}}]"

  let result = home_assistant.parse_climate_entities(json)

  let assert Ok([entity]) = result
  entity.hvac_mode |> should.equal(mode.HvacOff)
  entity.is_heating |> should.be_false
}

pub fn parse_climate_entities_handles_auto_mode_test() {
  let json =
    "[{\"entity_id\":\"climate.kitchen_trv\",\"state\":\"auto\",\"attributes\":{\"current_temperature\":19.5,\"temperature\":20.0,\"hvac_action\":\"heating\",\"friendly_name\":\"Kitchen TRV\"}}]"

  let result = home_assistant.parse_climate_entities(json)

  let assert Ok([entity]) = result
  entity.hvac_mode |> should.equal(mode.HvacAuto)
}

pub fn parse_climate_entities_handles_missing_temperatures_test() {
  // Some entities might have null temperatures
  let json =
    "[{\"entity_id\":\"climate.hallway_trv\",\"state\":\"heat\",\"attributes\":{\"current_temperature\":null,\"temperature\":null,\"hvac_action\":\"idle\",\"friendly_name\":\"Hallway TRV\"}}]"

  let result = home_assistant.parse_climate_entities(json)

  let assert Ok([entity]) = result
  entity.current_temperature |> should.equal(None)
  entity.target_temperature |> should.equal(None)
}

pub fn parse_climate_entities_filters_non_climate_entities_test() {
  // Should only return climate.* entities, not sensors, lights, etc.
  let json =
    "[{\"entity_id\":\"sensor.temperature\",\"state\":\"22.5\",\"attributes\":{}},{\"entity_id\":\"climate.lounge_trv\",\"state\":\"heat\",\"attributes\":{\"current_temperature\":20.0,\"temperature\":21.0,\"hvac_action\":\"idle\"}}]"

  let result = home_assistant.parse_climate_entities(json)

  let assert Ok(entities) = result
  // Should only have the climate entity
  list.length(entities) |> should.equal(1)
}

pub fn parse_climate_entities_handles_empty_array_test() {
  let json = "[]"

  let result = home_assistant.parse_climate_entities(json)

  let assert Ok(entities) = result
  entities |> should.equal([])
}

pub fn parse_climate_entities_returns_error_for_invalid_json_test() {
  let json = "not valid json"

  let result = home_assistant.parse_climate_entities(json)

  result |> should.be_error
}

pub fn parse_climate_entities_handles_unavailable_state_test() {
  // Unavailable entities should be parsed but marked appropriately
  let json =
    "[{\"entity_id\":\"climate.garage_trv\",\"state\":\"unavailable\",\"attributes\":{}}]"

  let result = home_assistant.parse_climate_entities(json)

  let assert Ok([entity]) = result
  entity.hvac_mode |> should.equal(mode.HvacOff)
  entity.is_available |> should.be_false
}

// -----------------------------------------------------------------------------
// find_input_button_state tests
// -----------------------------------------------------------------------------

pub fn find_input_button_state_extracts_state_for_matching_entity_test() {
  // input_button entities have a state that's a timestamp of last press
  let json =
    "[{\"entity_id\":\"input_button.goodnight\",\"state\":\"2026-01-03T10:30:00+00:00\",\"attributes\":{\"friendly_name\":\"Goodnight Button\"}}]"

  let result =
    home_assistant.find_input_button_state(json, "input_button.goodnight")

  result |> should.equal(Ok("2026-01-03T10:30:00+00:00"))
}

pub fn find_input_button_state_returns_error_when_entity_not_found_test() {
  let json =
    "[{\"entity_id\":\"input_button.other\",\"state\":\"2026-01-03T10:30:00+00:00\",\"attributes\":{}}]"

  let result =
    home_assistant.find_input_button_state(json, "input_button.goodnight")

  result
  |> should.equal(
    Error(home_assistant.EntityNotFound("input_button.goodnight")),
  )
}

pub fn find_input_button_state_finds_entity_among_mixed_entities_test() {
  // Real HA response has many entity types
  let json =
    "[{\"entity_id\":\"sensor.temperature\",\"state\":\"22.5\",\"attributes\":{}},{\"entity_id\":\"input_button.goodnight\",\"state\":\"2026-01-03T15:45:00+00:00\",\"attributes\":{}},{\"entity_id\":\"climate.lounge\",\"state\":\"heat\",\"attributes\":{}}]"

  let result =
    home_assistant.find_input_button_state(json, "input_button.goodnight")

  result |> should.equal(Ok("2026-01-03T15:45:00+00:00"))
}

// -----------------------------------------------------------------------------
// ha_client_from_env tests
// -----------------------------------------------------------------------------

pub fn ha_client_from_env_returns_client_when_both_vars_set_test() {
  // Set up env vars
  envoy.set("SUPERVISOR_URL", "http://supervisor/core")
  envoy.set("SUPERVISOR_TOKEN", "my-secret-token")

  let result = home_assistant.ha_client_from_env()

  result
  |> should.equal(Ok(HaClient("http://supervisor/core", "my-secret-token")))

  // Clean up
  envoy.unset("SUPERVISOR_URL")
  envoy.unset("SUPERVISOR_TOKEN")
}

pub fn ha_client_from_env_returns_error_when_url_not_set_test() {
  // Ensure URL is not set but token is
  envoy.unset("SUPERVISOR_URL")
  envoy.set("SUPERVISOR_TOKEN", "my-token")

  let result = home_assistant.ha_client_from_env()

  result |> should.equal(Error(home_assistant.EnvVarNotSet("SUPERVISOR_URL")))

  // Clean up
  envoy.unset("SUPERVISOR_TOKEN")
}

pub fn ha_client_from_env_returns_error_when_token_not_set_test() {
  // Ensure token is not set but URL is
  envoy.set("SUPERVISOR_URL", "http://supervisor/core")
  envoy.unset("SUPERVISOR_TOKEN")

  let result = home_assistant.ha_client_from_env()

  result |> should.equal(Error(home_assistant.EnvVarNotSet("SUPERVISOR_TOKEN")))

  // Clean up
  envoy.unset("SUPERVISOR_URL")
}

pub fn ha_client_from_env_returns_error_when_neither_var_set_test() {
  // Ensure neither is set
  envoy.unset("SUPERVISOR_URL")
  envoy.unset("SUPERVISOR_TOKEN")

  let result = home_assistant.ha_client_from_env()

  // Should fail on the first missing var (URL)
  result |> should.equal(Error(home_assistant.EnvVarNotSet("SUPERVISOR_URL")))
}

// -----------------------------------------------------------------------------
// error_to_string tests
// -----------------------------------------------------------------------------

pub fn error_to_string_formats_connection_error_test() {
  let err = home_assistant.ConnectionError("Failed to connect")

  home_assistant.error_to_string(err)
  |> should.equal("ConnectionError: Failed to connect")
}

pub fn error_to_string_formats_authentication_error_test() {
  let err = home_assistant.AuthenticationError

  home_assistant.error_to_string(err)
  |> should.equal("AuthenticationError")
}

pub fn error_to_string_formats_entity_not_found_test() {
  let err = home_assistant.EntityNotFound("climate.missing_trv")

  home_assistant.error_to_string(err)
  |> should.equal("EntityNotFound: climate.missing_trv")
}

pub fn error_to_string_formats_api_error_test() {
  let err = home_assistant.ApiError(500, "Internal Server Error")

  home_assistant.error_to_string(err)
  |> should.equal("ApiError(500): Internal Server Error")
}

pub fn error_to_string_formats_json_parse_error_test() {
  let err = home_assistant.JsonParseError("Unexpected token")

  home_assistant.error_to_string(err)
  |> should.equal("JsonParseError: Unexpected token")
}

pub fn error_to_string_formats_env_var_not_set_test() {
  let err = home_assistant.EnvVarNotSet("SUPERVISOR_URL")

  home_assistant.error_to_string(err)
  |> should.equal("EnvVarNotSet: SUPERVISOR_URL")
}

// -----------------------------------------------------------------------------
// parse_sensor_entities tests
// -----------------------------------------------------------------------------

pub fn parse_sensor_entities_parses_single_temperature_sensor_test() {
  let json =
    "[{\"entity_id\":\"sensor.lounge_temperature\",\"state\":\"20.5\",\"attributes\":{\"unit_of_measurement\":\"°C\",\"friendly_name\":\"Lounge Temperature\"}}]"

  let result = home_assistant.parse_sensor_entities(json)

  let assert Ok(entities) = result
  let assert [entity] = entities

  let assert Ok(expected_id) =
    entity_id.sensor_entity_id("sensor.lounge_temperature")
  entity.entity_id |> should.equal(expected_id)
  entity.temperature |> should.equal(Some(temperature.temperature(20.5)))
}

pub fn parse_sensor_entities_handles_integer_temperature_test() {
  let json =
    "[{\"entity_id\":\"sensor.bedroom_temp\",\"state\":\"19\",\"attributes\":{}}]"

  let result = home_assistant.parse_sensor_entities(json)

  let assert Ok([entity]) = result
  entity.temperature |> should.equal(Some(temperature.temperature(19.0)))
}

pub fn parse_sensor_entities_filters_non_sensor_entities_test() {
  let json =
    "[{\"entity_id\":\"climate.lounge_trv\",\"state\":\"heat\",\"attributes\":{}},{\"entity_id\":\"sensor.lounge_temperature\",\"state\":\"21.0\",\"attributes\":{}},{\"entity_id\":\"light.lounge\",\"state\":\"on\",\"attributes\":{}}]"

  let result = home_assistant.parse_sensor_entities(json)

  let assert Ok(entities) = result
  list.length(entities) |> should.equal(1)
}

pub fn parse_sensor_entities_handles_unavailable_sensor_test() {
  let json =
    "[{\"entity_id\":\"sensor.garage_temp\",\"state\":\"unavailable\",\"attributes\":{}}]"

  let result = home_assistant.parse_sensor_entities(json)

  let assert Ok([entity]) = result
  entity.temperature |> should.equal(None)
  entity.is_available |> should.be_false
}

pub fn parse_sensor_entities_handles_unknown_state_test() {
  let json =
    "[{\"entity_id\":\"sensor.hallway_temp\",\"state\":\"unknown\",\"attributes\":{}}]"

  let result = home_assistant.parse_sensor_entities(json)

  let assert Ok([entity]) = result
  entity.temperature |> should.equal(None)
  entity.is_available |> should.be_false
}

pub fn parse_sensor_entities_handles_empty_array_test() {
  let json = "[]"

  let result = home_assistant.parse_sensor_entities(json)

  let assert Ok(entities) = result
  entities |> should.equal([])
}

pub fn parse_sensor_entities_returns_error_for_invalid_json_test() {
  let json = "not valid json"

  let result = home_assistant.parse_sensor_entities(json)

  result |> should.be_error
}

pub fn parse_sensor_entities_handles_multiple_sensors_test() {
  let json =
    "[{\"entity_id\":\"sensor.lounge_temperature\",\"state\":\"20.5\",\"attributes\":{}},{\"entity_id\":\"sensor.bedroom_temperature\",\"state\":\"18.0\",\"attributes\":{}}]"

  let result = home_assistant.parse_sensor_entities(json)

  let assert Ok(entities) = result
  list.length(entities) |> should.equal(2)
}
