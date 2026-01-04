//// Room adjustments persistence module.
////
//// Handles loading and saving room temperature adjustments to/from a JSON file.
//// Format matches TypeScript implementation: [{"roomName": "...", "adjustment": N}, ...]

import envoy
import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import simplifile

/// A single room's temperature adjustment
pub type RoomAdjustment {
  RoomAdjustment(room_name: String, adjustment: Float)
}

/// Errors that can occur during persistence operations
pub type PersistenceError {
  JsonParseError(message: String)
  FileWriteError(message: String)
}

/// Parse a JSON string into a list of room adjustments
pub fn parse(json_string: String) -> Result(List(RoomAdjustment), PersistenceError) {
  json.parse(json_string, adjustments_decoder())
  |> result.map_error(fn(err) {
    JsonParseError("Failed to parse adjustments JSON: " <> string.inspect(err))
  })
}

/// Serialize a list of room adjustments to a JSON string
pub fn to_json(adjustments: List(RoomAdjustment)) -> String {
  adjustments
  |> list.map(fn(adj) {
    json.object([
      #("roomName", json.string(adj.room_name)),
      #("adjustment", json.float(adj.adjustment)),
    ])
  })
  |> json.preprocessed_array
  |> json.to_string
}

/// Load room adjustments from a file.
/// Returns an empty list if the file doesn't exist (graceful degradation).
pub fn load(path: String) -> Result(List(RoomAdjustment), PersistenceError) {
  case simplifile.read(path) {
    Ok(contents) -> parse(contents)
    Error(_) -> Ok([])
    // File doesn't exist, return empty list
  }
}

/// Save room adjustments to a file.
pub fn save(
  path: String,
  adjustments: List(RoomAdjustment),
) -> Result(Nil, PersistenceError) {
  let json_str = to_json(adjustments)
  simplifile.write(path, json_str)
  |> result.map_error(fn(err) {
    FileWriteError("Failed to write adjustments file: " <> simplifile.describe_error(err))
  })
}

/// Get the path from the ROOM_ADJUSTMENTS_PATH environment variable.
pub fn path_from_env() -> Result(String, Nil) {
  envoy.get("ROOM_ADJUSTMENTS_PATH")
  |> result.map_error(fn(_) { Nil })
}

/// Load room adjustments from the ROOM_ADJUSTMENTS_PATH environment variable.
/// Returns an empty list if the env var is not set (graceful degradation).
pub fn load_from_env() -> Result(List(RoomAdjustment), PersistenceError) {
  case path_from_env() {
    Ok(path) -> load(path)
    Error(_) -> Ok([])
    // Env var not set, return empty list
  }
}

/// Get the adjustment for a room by name.
/// Returns 0.0 if the room is not found.
pub fn get_adjustment(adjustments: List(RoomAdjustment), room_name: String) -> Float {
  adjustments
  |> list.find(fn(adj) { adj.room_name == room_name })
  |> result.map(fn(adj) { adj.adjustment })
  |> result.unwrap(0.0)
}

// -----------------------------------------------------------------------------
// Decoders
// -----------------------------------------------------------------------------

fn adjustments_decoder() -> Decoder(List(RoomAdjustment)) {
  decode.list(adjustment_decoder())
}

fn adjustment_decoder() -> Decoder(RoomAdjustment) {
  decode.field("roomName", decode.string, fn(room_name) {
    decode.field("adjustment", number_decoder(), fn(adjustment) {
      decode.success(RoomAdjustment(room_name: room_name, adjustment: adjustment))
    })
  })
}

fn number_decoder() -> Decoder(Float) {
  // JSON numbers can be int or float, we want them as Float
  decode.one_of(decode.float, [
    decode.then(decode.int, fn(i) { decode.success(int.to_float(i)) }),
  ])
}
