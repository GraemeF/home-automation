//// Fake Home Assistant HTTP server for end-to-end testing.
////
//// This module provides a configurable HTTP server that mimics the Home Assistant
//// REST API. It supports:
//// - GET /api/states - returns configurable entity states
//// - POST /api/services/climate/set_temperature - records calls
//// - POST /api/services/climate/set_hvac_mode - records calls
//// - Bearer token authentication

import deep_heating/entity_id.{type ClimateEntityId, type SensorEntityId}
import deep_heating/mode.{type HvacMode}
import deep_heating/temperature.{type Temperature}
import gleam/bit_array
import gleam/bytes_tree
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/erlang/process.{type Subject}
import gleam/float
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result
import gleam/string
import mist.{type Connection, type ResponseData}

// -----------------------------------------------------------------------------
// Entity State Types
// -----------------------------------------------------------------------------

/// State for a fake climate entity
pub type ClimateEntityState {
  ClimateEntityState(
    current_temperature: Option(Temperature),
    target_temperature: Option(Temperature),
    hvac_mode: HvacMode,
    hvac_action: Option(String),
  )
}

/// State for a fake sensor entity
pub type SensorEntityState {
  SensorEntityState(temperature: Option(Temperature), is_available: Bool)
}

// -----------------------------------------------------------------------------
// Server State and Messages
// -----------------------------------------------------------------------------

/// Internal server state (public for internal messaging)
pub type ServerState {
  ServerState(
    token: String,
    climate_entities: Dict(ClimateEntityId, ClimateEntityState),
    sensor_entities: Dict(SensorEntityId, SensorEntityState),
    input_buttons: Dict(String, String),
    set_temperature_calls: List(#(ClimateEntityId, Temperature)),
    set_hvac_mode_calls: List(#(ClimateEntityId, HvacMode)),
  )
}

/// Messages for the state actor
pub type StateMessage {
  SetClimateEntity(ClimateEntityId, ClimateEntityState)
  SetSensorEntity(SensorEntityId, SensorEntityState)
  SetInputButton(String, String)
  GetSetTemperatureCalls(Subject(List(#(ClimateEntityId, Temperature))))
  GetSetHvacModeCalls(Subject(List(#(ClimateEntityId, HvacMode))))
  ClearCalls
  RecordSetTemperatureCall(ClimateEntityId, Temperature)
  RecordSetHvacModeCall(ClimateEntityId, HvacMode)
  GetState(Subject(ServerState))
}

/// Handle to a running fake server
pub opaque type Server {
  Server(state_actor: Subject(StateMessage))
}

// -----------------------------------------------------------------------------
// Public API
// -----------------------------------------------------------------------------

/// Start a fake Home Assistant server on the specified port.
pub fn start(port: Int, token: String) -> Result(Server, String) {
  // Start the state actor
  let state_actor_result =
    actor.new(
      ServerState(
        token:,
        climate_entities: dict.new(),
        sensor_entities: dict.new(),
        input_buttons: dict.new(),
        set_temperature_calls: [],
        set_hvac_mode_calls: [],
      ),
    )
    |> actor.on_message(handle_state_message)
    |> actor.start

  case state_actor_result {
    Ok(started) -> {
      let state_actor = started.data
      // Start the HTTP server
      let handler = fn(request: Request(Connection)) -> Response(ResponseData) {
        handle_request(request, state_actor, token)
      }

      case
        mist.new(handler)
        |> mist.bind("127.0.0.1")
        |> mist.port(port)
        |> mist.start
      {
        Ok(_) -> Ok(Server(state_actor:))
        Error(e) -> Error("Failed to start HTTP server: " <> string.inspect(e))
      }
    }
    Error(e) -> Error("Failed to start state actor: " <> string.inspect(e))
  }
}

/// Stop the fake server.
/// Note: mist doesn't provide a stop function, but the actor stops cleanly
pub fn stop(_server: Server) -> Nil {
  // The mist server will be cleaned up when the test process exits
  // We can't explicitly stop it, but test isolation via ports handles this
  Nil
}

/// Configure a climate entity's state.
pub fn set_climate_entity(
  server: Server,
  entity_id: ClimateEntityId,
  state: ClimateEntityState,
) -> Nil {
  process.send(server.state_actor, SetClimateEntity(entity_id, state))
}

/// Configure a sensor entity's state.
pub fn set_sensor_entity(
  server: Server,
  entity_id: SensorEntityId,
  state: SensorEntityState,
) -> Nil {
  process.send(server.state_actor, SetSensorEntity(entity_id, state))
}

/// Configure an input_button entity's state.
pub fn set_input_button(server: Server, entity_id: String, state: String) -> Nil {
  process.send(server.state_actor, SetInputButton(entity_id, state))
}

/// Get all recorded set_temperature calls.
pub fn get_set_temperature_calls(
  server: Server,
) -> List(#(ClimateEntityId, Temperature)) {
  let reply_to = process.new_subject()
  process.send(server.state_actor, GetSetTemperatureCalls(reply_to))
  let assert Ok(result) = process.receive(reply_to, 1000)
  result
}

/// Get all recorded set_hvac_mode calls.
pub fn get_set_hvac_mode_calls(
  server: Server,
) -> List(#(ClimateEntityId, HvacMode)) {
  let reply_to = process.new_subject()
  process.send(server.state_actor, GetSetHvacModeCalls(reply_to))
  let assert Ok(result) = process.receive(reply_to, 1000)
  result
}

/// Clear all recorded API calls.
pub fn clear_calls(server: Server) -> Nil {
  process.send(server.state_actor, ClearCalls)
}

// -----------------------------------------------------------------------------
// State Actor Implementation
// -----------------------------------------------------------------------------

fn handle_state_message(
  state: ServerState,
  message: StateMessage,
) -> actor.Next(ServerState, StateMessage) {
  case message {
    SetClimateEntity(entity_id, entity_state) -> {
      let new_entities =
        dict.insert(state.climate_entities, entity_id, entity_state)
      actor.continue(ServerState(..state, climate_entities: new_entities))
    }

    SetSensorEntity(entity_id, entity_state) -> {
      let new_entities =
        dict.insert(state.sensor_entities, entity_id, entity_state)
      actor.continue(ServerState(..state, sensor_entities: new_entities))
    }

    SetInputButton(entity_id, button_state) -> {
      let new_buttons =
        dict.insert(state.input_buttons, entity_id, button_state)
      actor.continue(ServerState(..state, input_buttons: new_buttons))
    }

    GetSetTemperatureCalls(reply_to) -> {
      process.send(reply_to, state.set_temperature_calls)
      actor.continue(state)
    }

    GetSetHvacModeCalls(reply_to) -> {
      process.send(reply_to, state.set_hvac_mode_calls)
      actor.continue(state)
    }

    ClearCalls -> {
      actor.continue(
        ServerState(..state, set_temperature_calls: [], set_hvac_mode_calls: []),
      )
    }

    RecordSetTemperatureCall(entity_id, temp) -> {
      let new_calls =
        list.append(state.set_temperature_calls, [#(entity_id, temp)])
      actor.continue(ServerState(..state, set_temperature_calls: new_calls))
    }

    RecordSetHvacModeCall(entity_id, hvac_mode) -> {
      let new_calls =
        list.append(state.set_hvac_mode_calls, [#(entity_id, hvac_mode)])
      actor.continue(ServerState(..state, set_hvac_mode_calls: new_calls))
    }

    GetState(reply_to) -> {
      process.send(reply_to, state)
      actor.continue(state)
    }
  }
}

// -----------------------------------------------------------------------------
// HTTP Request Handling
// -----------------------------------------------------------------------------

fn handle_request(
  request: Request(Connection),
  state_actor: Subject(StateMessage),
  expected_token: String,
) -> Response(ResponseData) {
  // Check authorization
  case check_auth(request, expected_token) {
    False -> unauthorized_response()
    True -> {
      case request.path_segments(request), request.method {
        // GET /api/states
        ["api", "states"], http.Get -> handle_get_states(state_actor)

        // POST /api/services/climate/set_temperature
        ["api", "services", "climate", "set_temperature"], http.Post ->
          handle_set_temperature(request, state_actor)

        // POST /api/services/climate/set_hvac_mode
        ["api", "services", "climate", "set_hvac_mode"], http.Post ->
          handle_set_hvac_mode(request, state_actor)

        // 404 for everything else
        _, _ -> not_found_response()
      }
    }
  }
}

fn check_auth(request: Request(Connection), expected_token: String) -> Bool {
  case request.get_header(request, "authorization") {
    Ok(header) -> header == "Bearer " <> expected_token
    Error(_) -> False
  }
}

fn unauthorized_response() -> Response(ResponseData) {
  response.new(401)
  |> response.set_body(
    mist.Bytes(bytes_tree.from_string("{\"error\": \"Unauthorized\"}")),
  )
  |> response.set_header("content-type", "application/json")
}

fn not_found_response() -> Response(ResponseData) {
  response.new(404)
  |> response.set_body(
    mist.Bytes(bytes_tree.from_string("{\"error\": \"Not found\"}")),
  )
  |> response.set_header("content-type", "application/json")
}

fn handle_get_states(
  state_actor: Subject(StateMessage),
) -> Response(ResponseData) {
  // Get current state from actor
  let reply_to = process.new_subject()
  process.send(state_actor, GetState(reply_to))
  let assert Ok(state) = process.receive(reply_to, 1000)

  let entities = build_entities_json(state)
  let body = json.to_string(json.array(entities, fn(x) { x }))

  response.new(200)
  |> response.set_body(mist.Bytes(bytes_tree.from_string(body)))
  |> response.set_header("content-type", "application/json")
}

fn build_entities_json(state: ServerState) -> List(json.Json) {
  let climate_entities =
    dict.to_list(state.climate_entities)
    |> list.map(fn(pair) {
      let #(entity_id, entity_state) = pair
      climate_entity_to_json(entity_id, entity_state)
    })

  let sensor_entities =
    dict.to_list(state.sensor_entities)
    |> list.map(fn(pair) {
      let #(entity_id, entity_state) = pair
      sensor_entity_to_json(entity_id, entity_state)
    })

  let input_buttons =
    dict.to_list(state.input_buttons)
    |> list.map(fn(pair) {
      let #(entity_id, button_state) = pair
      input_button_to_json(entity_id, button_state)
    })

  list.flatten([climate_entities, sensor_entities, input_buttons])
}

fn climate_entity_to_json(
  entity_id: ClimateEntityId,
  state: ClimateEntityState,
) -> json.Json {
  let hvac_mode_str = mode.hvac_mode_to_string(state.hvac_mode)

  let attributes =
    [
      #(
        "friendly_name",
        json.string(entity_id.climate_entity_id_to_string(entity_id)),
      ),
    ]
    |> add_optional_float("current_temperature", state.current_temperature)
    |> add_optional_float("temperature", state.target_temperature)
    |> add_optional_string("hvac_action", state.hvac_action)

  json.object([
    #(
      "entity_id",
      json.string(entity_id.climate_entity_id_to_string(entity_id)),
    ),
    #("state", json.string(hvac_mode_str)),
    #("attributes", json.object(attributes)),
  ])
}

fn sensor_entity_to_json(
  entity_id: SensorEntityId,
  state: SensorEntityState,
) -> json.Json {
  let state_str = case state.is_available, state.temperature {
    False, _ -> "unavailable"
    True, None -> "unknown"
    True, Some(temp) -> float.to_string(temperature.unwrap(temp))
  }

  json.object([
    #("entity_id", json.string(entity_id.sensor_entity_id_to_string(entity_id))),
    #("state", json.string(state_str)),
    #("attributes", json.object([])),
  ])
}

fn input_button_to_json(entity_id: String, state: String) -> json.Json {
  json.object([
    #("entity_id", json.string(entity_id)),
    #("state", json.string(state)),
    #("attributes", json.object([])),
  ])
}

fn add_optional_float(
  attrs: List(#(String, json.Json)),
  key: String,
  value: Option(Temperature),
) -> List(#(String, json.Json)) {
  case value {
    Some(temp) ->
      list.append(attrs, [#(key, json.float(temperature.unwrap(temp)))])
    None -> list.append(attrs, [#(key, json.null())])
  }
}

fn add_optional_string(
  attrs: List(#(String, json.Json)),
  key: String,
  value: Option(String),
) -> List(#(String, json.Json)) {
  case value {
    Some(s) -> list.append(attrs, [#(key, json.string(s))])
    None -> attrs
  }
}

fn handle_set_temperature(
  request: Request(Connection),
  state_actor: Subject(StateMessage),
) -> Response(ResponseData) {
  // Read the request body
  case mist.read_body(request, 1024 * 64) {
    Ok(req_with_body) -> {
      // Parse the JSON body
      case parse_set_temperature_body(req_with_body.body) {
        Ok(#(entity_id, temp)) -> {
          // Record the call
          process.send(state_actor, RecordSetTemperatureCall(entity_id, temp))
          ok_response()
        }
        Error(_) -> bad_request_response()
      }
    }
    Error(_) -> bad_request_response()
  }
}

fn handle_set_hvac_mode(
  request: Request(Connection),
  state_actor: Subject(StateMessage),
) -> Response(ResponseData) {
  // Read the request body
  case mist.read_body(request, 1024 * 64) {
    Ok(req_with_body) -> {
      // Parse the JSON body
      case parse_set_hvac_mode_body(req_with_body.body) {
        Ok(#(entity_id, hvac_mode)) -> {
          // Record the call
          process.send(state_actor, RecordSetHvacModeCall(entity_id, hvac_mode))
          ok_response()
        }
        Error(_) -> bad_request_response()
      }
    }
    Error(_) -> bad_request_response()
  }
}

fn parse_set_temperature_body(
  body: BitArray,
) -> Result(#(ClimateEntityId, Temperature), Nil) {
  let body_string = bit_array_to_string(body)
  let decoder =
    decode.field("entity_id", decode.string, fn(eid_str) {
      decode.field("temperature", decode.float, fn(temp) {
        decode.success(#(eid_str, temp))
      })
    })

  json.parse(body_string, decoder)
  |> result.map_error(fn(_) { Nil })
  |> result.try(fn(pair) {
    let #(eid_str, temp_float) = pair
    case entity_id.climate_entity_id(eid_str) {
      Ok(eid) -> Ok(#(eid, temperature.temperature(temp_float)))
      Error(_) -> Error(Nil)
    }
  })
}

fn parse_set_hvac_mode_body(
  body: BitArray,
) -> Result(#(ClimateEntityId, HvacMode), Nil) {
  let body_string = bit_array_to_string(body)
  let decoder =
    decode.field("entity_id", decode.string, fn(eid_str) {
      decode.field("hvac_mode", decode.string, fn(hvac_mode_str) {
        decode.success(#(eid_str, hvac_mode_str))
      })
    })

  json.parse(body_string, decoder)
  |> result.map_error(fn(_) { Nil })
  |> result.try(fn(pair) {
    let #(eid_str, hvac_mode_str) = pair
    case entity_id.climate_entity_id(eid_str), parse_hvac_mode(hvac_mode_str) {
      Ok(eid), Ok(hvac_mode) -> Ok(#(eid, hvac_mode))
      _, _ -> Error(Nil)
    }
  })
}

fn parse_hvac_mode(s: String) -> Result(HvacMode, Nil) {
  case s {
    "heat" -> Ok(mode.HvacHeat)
    "auto" -> Ok(mode.HvacAuto)
    "off" -> Ok(mode.HvacOff)
    _ -> Error(Nil)
  }
}

fn ok_response() -> Response(ResponseData) {
  response.new(200)
  |> response.set_body(mist.Bytes(bytes_tree.from_string("[]")))
  |> response.set_header("content-type", "application/json")
}

fn bad_request_response() -> Response(ResponseData) {
  response.new(400)
  |> response.set_body(
    mist.Bytes(bytes_tree.from_string("{\"error\": \"Bad request\"}")),
  )
  |> response.set_header("content-type", "application/json")
}

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

fn bit_array_to_string(bits: BitArray) -> String {
  case bit_array.to_string(bits) {
    Ok(s) -> s
    Error(_) -> ""
  }
}
