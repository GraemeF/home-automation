import deep_heating/entity_id
import deep_heating/home_assistant.{HaClient}
import deep_heating/mode
import deep_heating/temperature
import gleam/http
import gleam/http/request
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
