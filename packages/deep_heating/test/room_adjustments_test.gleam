//// Tests for room_adjustments module - persistence of room temperature adjustments

import deep_heating/room_adjustments
import envoy
import gleeunit/should
import simplifile

// =============================================================================
// Type Tests
// =============================================================================

pub fn room_adjustment_has_correct_fields_test() {
  let adj =
    room_adjustments.RoomAdjustment(room_name: "lounge", adjustment: 1.5)
  adj.room_name |> should.equal("lounge")
  adj.adjustment |> should.equal(1.5)
}

// =============================================================================
// Parse Tests
// =============================================================================

pub fn parse_valid_json_array_test() {
  let json =
    "[
      {\"roomName\": \"lounge\", \"adjustment\": 1.5},
      {\"roomName\": \"bedroom\", \"adjustment\": -0.5}
    ]"

  let result = room_adjustments.parse(json)
  result |> should.be_ok

  let adjustments = result |> should.be_ok
  adjustments
  |> should.equal([
    room_adjustments.RoomAdjustment(room_name: "lounge", adjustment: 1.5),
    room_adjustments.RoomAdjustment(room_name: "bedroom", adjustment: -0.5),
  ])
}

pub fn parse_empty_array_test() {
  let json = "[]"
  let result = room_adjustments.parse(json)
  result |> should.be_ok

  let adjustments = result |> should.be_ok
  adjustments |> should.equal([])
}

pub fn parse_integer_adjustment_test() {
  // JSON numbers can be ints or floats
  let json = "[{\"roomName\": \"kitchen\", \"adjustment\": 2}]"
  let result = room_adjustments.parse(json)
  result |> should.be_ok

  let adjustments = result |> should.be_ok
  adjustments
  |> should.equal([
    room_adjustments.RoomAdjustment(room_name: "kitchen", adjustment: 2.0),
  ])
}

pub fn parse_invalid_json_test() {
  let json = "not valid json"
  let result = room_adjustments.parse(json)
  result |> should.be_error
}

pub fn parse_missing_room_name_test() {
  let json = "[{\"adjustment\": 1.5}]"
  let result = room_adjustments.parse(json)
  result |> should.be_error
}

pub fn parse_missing_adjustment_test() {
  let json = "[{\"roomName\": \"lounge\"}]"
  let result = room_adjustments.parse(json)
  result |> should.be_error
}

// =============================================================================
// Serialize Tests
// =============================================================================

pub fn serialize_to_json_test() {
  let adjustments = [
    room_adjustments.RoomAdjustment(room_name: "lounge", adjustment: 1.5),
    room_adjustments.RoomAdjustment(room_name: "bedroom", adjustment: -0.5),
  ]

  let json = room_adjustments.to_json(adjustments)

  // Parse it back to verify it's valid
  let result = room_adjustments.parse(json)
  result |> should.be_ok
  result |> should.be_ok |> should.equal(adjustments)
}

pub fn serialize_empty_list_test() {
  let json = room_adjustments.to_json([])
  json |> should.equal("[]")
}

// =============================================================================
// File Loading Tests
// =============================================================================

pub fn load_from_file_valid_test() {
  let test_path = "/tmp/test_room_adjustments.json"
  let json =
    "[
      {\"roomName\": \"lounge\", \"adjustment\": 1.5}
    ]"
  let assert Ok(_) = simplifile.write(test_path, json)

  let result = room_adjustments.load(test_path)

  // Cleanup
  let _ = simplifile.delete(test_path)

  result |> should.be_ok
  let adjustments = result |> should.be_ok
  adjustments
  |> should.equal([
    room_adjustments.RoomAdjustment(room_name: "lounge", adjustment: 1.5),
  ])
}

pub fn load_from_file_not_found_returns_empty_list_test() {
  // When file doesn't exist, return empty list (not an error)
  // This matches TypeScript behaviour
  let result = room_adjustments.load("/tmp/nonexistent_adjustments.json")
  result |> should.be_ok
  result |> should.be_ok |> should.equal([])
}

pub fn load_from_file_invalid_json_returns_error_test() {
  let test_path = "/tmp/test_invalid_adjustments.json"
  let assert Ok(_) = simplifile.write(test_path, "not valid json")

  let result = room_adjustments.load(test_path)

  // Cleanup
  let _ = simplifile.delete(test_path)

  result |> should.be_error
}

// =============================================================================
// File Saving Tests
// =============================================================================

pub fn save_to_file_test() {
  let test_path = "/tmp/test_save_adjustments.json"
  let adjustments = [
    room_adjustments.RoomAdjustment(room_name: "lounge", adjustment: 1.5),
    room_adjustments.RoomAdjustment(room_name: "bedroom", adjustment: -0.5),
  ]

  let result = room_adjustments.save(test_path, adjustments)

  result |> should.be_ok

  // Read back and verify
  let loaded = room_adjustments.load(test_path)

  // Cleanup
  let _ = simplifile.delete(test_path)

  loaded |> should.be_ok |> should.equal(adjustments)
}

pub fn save_empty_list_test() {
  let test_path = "/tmp/test_save_empty_adjustments.json"

  let result = room_adjustments.save(test_path, [])
  result |> should.be_ok

  // Read back and verify
  let loaded = room_adjustments.load(test_path)

  // Cleanup
  let _ = simplifile.delete(test_path)

  loaded |> should.be_ok |> should.equal([])
}

// =============================================================================
// Environment Variable Tests
// =============================================================================

pub fn load_from_env_test() {
  let test_path = "/tmp/test_env_adjustments.json"
  let json = "[{\"roomName\": \"lounge\", \"adjustment\": 2.0}]"
  let assert Ok(_) = simplifile.write(test_path, json)

  envoy.set("ROOM_ADJUSTMENTS_PATH", test_path)

  let result = room_adjustments.load_from_env()

  // Cleanup
  envoy.unset("ROOM_ADJUSTMENTS_PATH")
  let _ = simplifile.delete(test_path)

  result |> should.be_ok
  result
  |> should.be_ok
  |> should.equal([
    room_adjustments.RoomAdjustment(room_name: "lounge", adjustment: 2.0),
  ])
}

pub fn load_from_env_not_set_returns_empty_test() {
  envoy.unset("ROOM_ADJUSTMENTS_PATH")

  let result = room_adjustments.load_from_env()

  // When env var not set, return empty list (graceful degradation)
  result |> should.be_ok
  result |> should.be_ok |> should.equal([])
}

pub fn get_path_from_env_test() {
  let test_path = "/some/path/adjustments.json"
  envoy.set("ROOM_ADJUSTMENTS_PATH", test_path)

  let result = room_adjustments.path_from_env()

  envoy.unset("ROOM_ADJUSTMENTS_PATH")

  result |> should.be_ok
  result |> should.be_ok |> should.equal(test_path)
}

pub fn get_path_from_env_not_set_test() {
  envoy.unset("ROOM_ADJUSTMENTS_PATH")

  let result = room_adjustments.path_from_env()

  result |> should.be_error
}

// =============================================================================
// Lookup Helper Tests
// =============================================================================

pub fn find_adjustment_for_room_test() {
  let adjustments = [
    room_adjustments.RoomAdjustment(room_name: "lounge", adjustment: 1.5),
    room_adjustments.RoomAdjustment(room_name: "bedroom", adjustment: -0.5),
  ]

  room_adjustments.get_adjustment(adjustments, "lounge")
  |> should.equal(1.5)

  room_adjustments.get_adjustment(adjustments, "bedroom")
  |> should.equal(-0.5)
}

pub fn find_adjustment_for_unknown_room_returns_zero_test() {
  let adjustments = [
    room_adjustments.RoomAdjustment(room_name: "lounge", adjustment: 1.5),
  ]

  room_adjustments.get_adjustment(adjustments, "unknown")
  |> should.equal(0.0)
}

pub fn find_adjustment_from_empty_list_returns_zero_test() {
  room_adjustments.get_adjustment([], "lounge")
  |> should.equal(0.0)
}
