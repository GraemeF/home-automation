// Home Assistant REST API client
// This module provides functions to interact with the Home Assistant API

import deep_heating/entity_id.{type ClimateEntityId}
import deep_heating/mode.{type HvacMode}
import deep_heating/temperature.{type Temperature}
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/httpc
import gleam/json
import gleam/result

/// Configuration for connecting to Home Assistant
pub type HaClient {
  HaClient(base_url: String, token: String)
}

/// Errors that can occur when communicating with Home Assistant
pub type HaError {
  ConnectionError(message: String)
  AuthenticationError
  EntityNotFound(entity_id: String)
  ApiError(status: Int, body: String)
  JsonParseError(message: String)
}

/// Build an HTTP request to fetch all entity states from Home Assistant.
/// Returns a Request that can be sent with httpc.send()
pub fn build_get_states_request(client: HaClient) -> Request(String) {
  let HaClient(base_url, token) = client
  let assert Ok(req) = request.to(base_url <> "/api/states")
  req
  |> request.prepend_header("authorization", "Bearer " <> token)
}

/// Build an HTTP request to set a TRV's target temperature.
pub fn build_set_temperature_request(
  client: HaClient,
  climate_entity_id: ClimateEntityId,
  target_temperature: Temperature,
) -> Request(String) {
  let HaClient(base_url, token) = client
  let assert Ok(req) =
    request.to(base_url <> "/api/services/climate/set_temperature")

  let body =
    json.object([
      #(
        "entity_id",
        json.string(entity_id.climate_entity_id_to_string(climate_entity_id)),
      ),
      #("temperature", json.float(temperature.unwrap(target_temperature))),
    ])
    |> json.to_string

  req
  |> request.set_method(http.Post)
  |> request.prepend_header("authorization", "Bearer " <> token)
  |> request.prepend_header("content-type", "application/json")
  |> request.set_body(body)
}

/// Build an HTTP request to set a TRV's HVAC mode.
pub fn build_set_hvac_mode_request(
  client: HaClient,
  climate_entity_id: ClimateEntityId,
  hvac_mode: HvacMode,
) -> Request(String) {
  let HaClient(base_url, token) = client
  let assert Ok(req) =
    request.to(base_url <> "/api/services/climate/set_hvac_mode")

  let body =
    json.object([
      #(
        "entity_id",
        json.string(entity_id.climate_entity_id_to_string(climate_entity_id)),
      ),
      #("hvac_mode", json.string(mode.hvac_mode_to_string(hvac_mode))),
    ])
    |> json.to_string

  req
  |> request.set_method(http.Post)
  |> request.prepend_header("authorization", "Bearer " <> token)
  |> request.prepend_header("content-type", "application/json")
  |> request.set_body(body)
}

// -----------------------------------------------------------------------------
// HTTP API Functions
// -----------------------------------------------------------------------------

/// Fetch all entity states from Home Assistant.
/// Returns the raw JSON response body.
pub fn get_states(client: HaClient) -> Result(String, HaError) {
  client
  |> build_get_states_request
  |> httpc.send
  |> result.map_error(fn(err) {
    ConnectionError("HTTP request failed: " <> httpc_error_to_string(err))
  })
  |> result.try(handle_response)
}

/// Set a TRV's target temperature.
pub fn set_temperature(
  client: HaClient,
  climate_entity_id: ClimateEntityId,
  target_temperature: Temperature,
) -> Result(Nil, HaError) {
  client
  |> build_set_temperature_request(climate_entity_id, target_temperature)
  |> httpc.send
  |> result.map_error(fn(err) {
    ConnectionError("HTTP request failed: " <> httpc_error_to_string(err))
  })
  |> result.try(handle_response)
  |> result.map(fn(_) { Nil })
}

/// Set a TRV's HVAC mode.
pub fn set_hvac_mode(
  client: HaClient,
  climate_entity_id: ClimateEntityId,
  hvac_mode: HvacMode,
) -> Result(Nil, HaError) {
  client
  |> build_set_hvac_mode_request(climate_entity_id, hvac_mode)
  |> httpc.send
  |> result.map_error(fn(err) {
    ConnectionError("HTTP request failed: " <> httpc_error_to_string(err))
  })
  |> result.try(handle_response)
  |> result.map(fn(_) { Nil })
}

// -----------------------------------------------------------------------------
// Internal Helpers
// -----------------------------------------------------------------------------

fn handle_response(resp: Response(String)) -> Result(String, HaError) {
  case resp.status {
    status if status >= 200 && status < 300 -> Ok(resp.body)
    401 -> Error(AuthenticationError)
    404 -> Error(EntityNotFound("Entity not found"))
    status -> Error(ApiError(status, resp.body))
  }
}

fn httpc_error_to_string(err: httpc.HttpError) -> String {
  case err {
    httpc.InvalidUtf8Response -> "Invalid UTF-8 response"
    httpc.FailedToConnect(_, _) -> "Failed to connect"
    httpc.ResponseTimeout -> "Response timeout"
  }
}
