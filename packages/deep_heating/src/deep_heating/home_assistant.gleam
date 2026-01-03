// Home Assistant REST API client
// This module provides functions to interact with the Home Assistant API

import deep_heating/entity_id.{type ClimateEntityId}
import deep_heating/mode.{type HvacMode}
import deep_heating/temperature.{type Temperature}
import gleam/dynamic/decode.{type Decoder}
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/httpc
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

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

// -----------------------------------------------------------------------------
// Climate Entity Parsing
// -----------------------------------------------------------------------------

/// A parsed climate entity from Home Assistant
pub type ClimateEntity {
  ClimateEntity(
    entity_id: ClimateEntityId,
    current_temperature: Option(Temperature),
    target_temperature: Option(Temperature),
    hvac_mode: HvacMode,
    is_heating: Bool,
    is_available: Bool,
  )
}

/// Raw entity for intermediate parsing (before filtering)
type RawEntity {
  RawEntity(
    entity_id: String,
    state: String,
    current_temperature: Option(Float),
    target_temperature: Option(Float),
    hvac_action: Option(String),
  )
}

/// Parse climate entities from HA API JSON response
pub fn parse_climate_entities(
  json_string: String,
) -> Result(List(ClimateEntity), HaError) {
  json.parse(json_string, decode.list(raw_entity_decoder()))
  |> result.map_error(fn(err) {
    JsonParseError("Failed to parse entities: " <> string.inspect(err))
  })
  |> result.map(fn(raw_entities) {
    raw_entities
    |> list.filter(fn(raw) { string.starts_with(raw.entity_id, "climate.") })
    |> list.filter_map(convert_raw_to_climate_entity)
  })
}

/// Decoder for a raw entity
fn raw_entity_decoder() -> Decoder(RawEntity) {
  // First, decode the required fields
  decode.field("entity_id", decode.string, fn(entity_id) {
    decode.field("state", decode.string, fn(state) {
      // Decode optional attributes
      // optionally_at returns default when path is missing
      // decode.optional handles null values
      let current_temp_decoder =
        decode.optionally_at(
          ["attributes", "current_temperature"],
          None,
          decode.optional(decode.float),
        )
      let target_temp_decoder =
        decode.optionally_at(
          ["attributes", "temperature"],
          None,
          decode.optional(decode.float),
        )
      let hvac_action_decoder =
        decode.optionally_at(
          ["attributes", "hvac_action"],
          None,
          decode.optional(decode.string),
        )

      // Combine the decoders
      decode.then(current_temp_decoder, fn(current_temp) {
        decode.then(target_temp_decoder, fn(target_temp) {
          decode.then(hvac_action_decoder, fn(hvac_action) {
            decode.success(RawEntity(
              entity_id: entity_id,
              state: state,
              current_temperature: current_temp,
              target_temperature: target_temp,
              hvac_action: hvac_action,
            ))
          })
        })
      })
    })
  })
}

/// Convert a raw entity to a ClimateEntity
fn convert_raw_to_climate_entity(raw: RawEntity) -> Result(ClimateEntity, Nil) {
  case entity_id.climate_entity_id(raw.entity_id) {
    Ok(eid) -> {
      let is_available = raw.state != "unavailable"
      let hvac_mode = parse_hvac_mode(raw.state)
      let is_heating = raw.hvac_action == Some("heating")
      let current_temp =
        option.map(raw.current_temperature, temperature.temperature)
      let target_temp =
        option.map(raw.target_temperature, temperature.temperature)

      Ok(ClimateEntity(
        entity_id: eid,
        current_temperature: current_temp,
        target_temperature: target_temp,
        hvac_mode: hvac_mode,
        is_heating: is_heating,
        is_available: is_available,
      ))
    }
    Error(_) -> Error(Nil)
  }
}

/// Parse HVAC mode from string
fn parse_hvac_mode(state: String) -> HvacMode {
  case state {
    "heat" -> mode.HvacHeat
    "auto" -> mode.HvacAuto
    "off" -> mode.HvacOff
    "unavailable" -> mode.HvacOff
    _ -> mode.HvacOff
  }
}
