import deep_heating/entity_id
import deep_heating/mode
import deep_heating/rooms/room_actor
import deep_heating/rooms/room_decision_actor
import deep_heating/temperature
import gleam/dict
import gleam/erlang/process.{type Name, type Subject}
import gleam/int
import gleam/list
import gleam/option
import gleam/otp/actor
import gleeunit/should
import test_helpers

// =============================================================================
// FFI for unique integer generation
// =============================================================================

@external(erlang, "erlang", "unique_integer")
fn unique_integer() -> Int

// =============================================================================
// Test Helpers
// =============================================================================

/// Create a mock TrvCommandAdapter that uses actor.named() and forwards to a spy.
/// Returns the adapter name and spy Subject for receiving commands.
fn make_mock_trv_adapter(
  test_id: String,
) -> #(
  Name(room_decision_actor.TrvCommand),
  Subject(room_decision_actor.TrvCommand),
) {
  let spy = process.new_subject()
  let name =
    process.new_name(
      "mock_trv_adapter_" <> test_id <> "_" <> int.to_string(unique_integer()),
    )

  // Start a mock actor that forwards messages to spy
  let assert Ok(_started) =
    actor.new(spy)
    |> actor.named(name)
    |> actor.on_message(fn(spy_subj, cmd) {
      process.send(spy_subj, cmd)
      actor.continue(spy_subj)
    })
    |> actor.start

  #(name, spy)
}

fn make_room_state_with_trv(
  room_temp room_temp: temperature.Temperature,
  target_temp target_temp: temperature.Temperature,
  trv_id trv_id: entity_id.ClimateEntityId,
  trv_temp trv_temp: temperature.Temperature,
) -> room_actor.RoomState {
  let trv_state =
    room_actor.TrvState(
      temperature: option.Some(trv_temp),
      target: option.Some(temperature.temperature(20.0)),
      mode: mode.HvacHeat,
      is_heating: False,
    )
  room_actor.RoomState(
    name: "lounge",
    temperature: option.Some(room_temp),
    target_temperature: option.Some(target_temp),
    house_mode: mode.HouseModeAuto,
    room_mode: mode.RoomModeAuto,
    adjustment: 0.0,
    trv_states: dict.from_list([#(trv_id, trv_state)]),
  )
}

// =============================================================================
// Actor Startup Tests
// =============================================================================

pub fn room_decision_actor_starts_successfully_test() {
  // Create a named mock TRV adapter
  let #(trv_adapter_name, _spy) = make_mock_trv_adapter("starts_successfully")

  // Decision actor should start successfully
  let result =
    room_decision_actor.start_with_trv_adapter_name(
      trv_adapter_name: trv_adapter_name,
    )
  should.be_ok(result)
}

// =============================================================================
// Target Computation Tests
// =============================================================================

pub fn sends_room_target_when_room_at_temperature_test() {
  // When room is at target temperature (within 0.5°C tolerance),
  // TRV should be set to the room target directly (no compensation)
  let #(trv_adapter_name, spy) = make_mock_trv_adapter("room_at_temp")

  let assert Ok(started) =
    room_decision_actor.start_with_trv_adapter_name(
      trv_adapter_name: trv_adapter_name,
    )

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  // Room at 20°C, target 20°C - TRV should be set to 20°C
  let room_state =
    make_room_state_with_trv(
      room_temp: temperature.temperature(20.0),
      target_temp: temperature.temperature(20.0),
      trv_id: trv_id,
      trv_temp: temperature.temperature(20.0),
    )

  // Send room state change to decision actor
  process.send(started.data, room_decision_actor.RoomStateChanged(room_state))

  // Should receive command to set TRV target
  let cmd =
    test_helpers.expect_receive(spy, 1000, "TRV command when room at target")

  let room_decision_actor.TrvCommand(entity_id, cmd_mode, target) = cmd
  entity_id |> should.equal(trv_id)
  cmd_mode |> should.equal(mode.HvacHeat)
  temperature.unwrap(target) |> should.equal(20.0)
}

pub fn pushes_trv_target_higher_when_room_is_cold_test() {
  // When room is cold, offset formula pushes TRV higher to compensate
  // Formula: trvTarget = roomTarget + trvTemp - roomTemp
  let #(trv_adapter_name, spy) = make_mock_trv_adapter("room_is_cold")

  let assert Ok(started) =
    room_decision_actor.start_with_trv_adapter_name(
      trv_adapter_name: trv_adapter_name,
    )

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  // Room at 19°C, target 20°C, TRV reads 20°C
  // Offset formula: 20 + 20 - 19 = 21°C
  let room_state =
    make_room_state_with_trv(
      room_temp: temperature.temperature(19.0),
      target_temp: temperature.temperature(20.0),
      trv_id: trv_id,
      trv_temp: temperature.temperature(20.0),
    )

  process.send(started.data, room_decision_actor.RoomStateChanged(room_state))

  let cmd =
    test_helpers.expect_receive(spy, 1000, "TRV command when room is cold")

  let room_decision_actor.TrvCommand(entity_id, cmd_mode, target) = cmd
  entity_id |> should.equal(trv_id)
  cmd_mode |> should.equal(mode.HvacHeat)
  // Offset formula: 20 + 20 - 19 = 21
  temperature.unwrap(target) |> should.equal(21.0)
}

pub fn backs_off_trv_when_room_is_hot_test() {
  // When room is hot, offset formula backs off TRV
  // Formula: trvTarget = roomTarget + trvTemp - roomTemp
  let #(trv_adapter_name, spy) = make_mock_trv_adapter("room_is_hot")

  let assert Ok(started) =
    room_decision_actor.start_with_trv_adapter_name(
      trv_adapter_name: trv_adapter_name,
    )

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  // Room at 21°C, target 20°C, TRV reads 20°C
  // Offset formula: 20 + 20 - 21 = 19°C
  let room_state =
    make_room_state_with_trv(
      room_temp: temperature.temperature(21.0),
      target_temp: temperature.temperature(20.0),
      trv_id: trv_id,
      trv_temp: temperature.temperature(20.0),
    )

  process.send(started.data, room_decision_actor.RoomStateChanged(room_state))

  let cmd =
    test_helpers.expect_receive(spy, 1000, "TRV command when room is hot")

  let room_decision_actor.TrvCommand(entity_id, cmd_mode, target) = cmd
  entity_id |> should.equal(trv_id)
  cmd_mode |> should.equal(mode.HvacHeat)
  // Offset formula: 20 + 20 - 21 = 19
  temperature.unwrap(target) |> should.equal(19.0)
}

pub fn uses_room_target_when_no_external_sensor_test() {
  // When there's no external temperature sensor, use the room target directly
  // (no compensation possible without knowing actual room temp)
  let #(trv_adapter_name, spy) = make_mock_trv_adapter("no_external_sensor")

  let assert Ok(started) =
    room_decision_actor.start_with_trv_adapter_name(
      trv_adapter_name: trv_adapter_name,
    )

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  // Room state with no external temperature sensor
  let trv_state =
    room_actor.TrvState(
      temperature: option.Some(temperature.temperature(20.0)),
      target: option.Some(temperature.temperature(20.0)),
      mode: mode.HvacHeat,
      is_heating: False,
    )
  let room_state =
    room_actor.RoomState(
      name: "lounge",
      temperature: option.None,
      // No external sensor!
      target_temperature: option.Some(temperature.temperature(20.0)),
      house_mode: mode.HouseModeAuto,
      room_mode: mode.RoomModeAuto,
      adjustment: 0.0,
      trv_states: dict.from_list([#(trv_id, trv_state)]),
    )

  process.send(started.data, room_decision_actor.RoomStateChanged(room_state))

  let cmd =
    test_helpers.expect_receive(
      spy,
      1000,
      "TRV command with no external sensor",
    )

  let room_decision_actor.TrvCommand(entity_id, cmd_mode, target) = cmd
  entity_id |> should.equal(trv_id)
  cmd_mode |> should.equal(mode.HvacHeat)
  // Should just use the room target directly
  temperature.unwrap(target) |> should.equal(20.0)
}

pub fn only_sends_command_when_target_differs_test() {
  // Should not send duplicate commands when computed target hasn't changed
  let #(trv_adapter_name, spy) = make_mock_trv_adapter("target_differs")

  let assert Ok(started) =
    room_decision_actor.start_with_trv_adapter_name(
      trv_adapter_name: trv_adapter_name,
    )

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  let room_state =
    make_room_state_with_trv(
      room_temp: temperature.temperature(20.0),
      target_temp: temperature.temperature(20.0),
      trv_id: trv_id,
      trv_temp: temperature.temperature(20.0),
    )

  // First update - should send command
  process.send(started.data, room_decision_actor.RoomStateChanged(room_state))
  let _cmd =
    test_helpers.expect_receive(
      spy,
      1000,
      "First TRV command before dedup test",
    )

  // Second update with same state - should NOT send command
  process.send(started.data, room_decision_actor.RoomStateChanged(room_state))

  // Give actor time to process
  process.sleep(50)

  // Should NOT receive a second command (timeout expected)
  let result = process.receive(spy, 100)
  result |> should.be_error
}

pub fn handles_multiple_trvs_in_room_test() {
  // When a room has multiple TRVs, all should receive SetTarget commands
  let #(trv_adapter_name, spy) = make_mock_trv_adapter("multiple_trvs")

  let assert Ok(started) =
    room_decision_actor.start_with_trv_adapter_name(
      trv_adapter_name: trv_adapter_name,
    )

  let assert Ok(trv1) = entity_id.climate_entity_id("climate.bedroom_trv_1")
  let assert Ok(trv2) = entity_id.climate_entity_id("climate.bedroom_trv_2")

  // Room state with two TRVs
  let trv_state1 =
    room_actor.TrvState(
      temperature: option.Some(temperature.temperature(20.0)),
      target: option.Some(temperature.temperature(20.0)),
      mode: mode.HvacHeat,
      is_heating: False,
    )
  let trv_state2 =
    room_actor.TrvState(
      temperature: option.Some(temperature.temperature(19.5)),
      target: option.Some(temperature.temperature(20.0)),
      mode: mode.HvacHeat,
      is_heating: False,
    )
  let room_state =
    room_actor.RoomState(
      name: "bedroom",
      temperature: option.Some(temperature.temperature(20.0)),
      target_temperature: option.Some(temperature.temperature(20.0)),
      house_mode: mode.HouseModeAuto,
      room_mode: mode.RoomModeAuto,
      adjustment: 0.0,
      trv_states: dict.from_list([#(trv1, trv_state1), #(trv2, trv_state2)]),
    )

  process.send(started.data, room_decision_actor.RoomStateChanged(room_state))

  // Should receive two commands - one for each TRV
  let cmd1 = test_helpers.expect_receive(spy, 1000, "First TRV command")
  let cmd2 = test_helpers.expect_receive(spy, 1000, "Second TRV command")

  // Collect the entity IDs that received commands
  let room_decision_actor.TrvCommand(id1, _, _) = cmd1
  let room_decision_actor.TrvCommand(id2, _, _) = cmd2
  let ids = [id1, id2]

  // Both TRVs should have received commands (order may vary)
  list.contains(ids, trv1) |> should.be_true
  list.contains(ids, trv2) |> should.be_true
}

// =============================================================================
// Fallback Handling Tests - graceful degradation when data is incomplete
// =============================================================================

pub fn handles_trv_with_missing_temperature_test() {
  // When a TRV has no temperature reading, the system should still work.
  // Uses room target directly (fallback: treat TRV temp as unknown)
  let #(trv_adapter_name, spy) = make_mock_trv_adapter("missing_temp")

  let assert Ok(started) =
    room_decision_actor.start_with_trv_adapter_name(
      trv_adapter_name: trv_adapter_name,
    )

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  // TRV state with no temperature reading
  let trv_state =
    room_actor.TrvState(
      temperature: option.None,
      // No temp reading!
      target: option.Some(temperature.temperature(20.0)),
      mode: mode.HvacHeat,
      is_heating: False,
    )
  let room_state =
    room_actor.RoomState(
      name: "lounge",
      temperature: option.Some(temperature.temperature(20.0)),
      target_temperature: option.Some(temperature.temperature(20.0)),
      house_mode: mode.HouseModeAuto,
      room_mode: mode.RoomModeAuto,
      adjustment: 0.0,
      trv_states: dict.from_list([#(trv_id, trv_state)]),
    )

  process.send(started.data, room_decision_actor.RoomStateChanged(room_state))

  // Should still receive a command (system degrades gracefully)
  let cmd =
    test_helpers.expect_receive(spy, 1000, "TRV command with missing temp")

  let room_decision_actor.TrvCommand(entity_id, cmd_mode, target) = cmd
  entity_id |> should.equal(trv_id)
  cmd_mode |> should.equal(mode.HvacHeat)
  // With no TRV temp data, should use room target directly
  temperature.unwrap(target) |> should.equal(20.0)
}

pub fn handles_trv_with_missing_target_test() {
  // When a TRV has no current target, the system should still compute and send one
  let #(trv_adapter_name, spy) = make_mock_trv_adapter("missing_target")

  let assert Ok(started) =
    room_decision_actor.start_with_trv_adapter_name(
      trv_adapter_name: trv_adapter_name,
    )

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  // TRV state with no target
  let trv_state =
    room_actor.TrvState(
      temperature: option.Some(temperature.temperature(20.0)),
      target: option.None,
      mode: mode.HvacHeat,
      is_heating: False,
    )
  let room_state =
    room_actor.RoomState(
      name: "lounge",
      temperature: option.Some(temperature.temperature(20.0)),
      target_temperature: option.Some(temperature.temperature(20.0)),
      house_mode: mode.HouseModeAuto,
      room_mode: mode.RoomModeAuto,
      adjustment: 0.0,
      trv_states: dict.from_list([#(trv_id, trv_state)]),
    )

  process.send(started.data, room_decision_actor.RoomStateChanged(room_state))

  // Should still send a command to set the target
  let cmd =
    test_helpers.expect_receive(spy, 1000, "TRV command with missing target")

  let room_decision_actor.TrvCommand(entity_id, cmd_mode, _target) = cmd
  entity_id |> should.equal(trv_id)
  cmd_mode |> should.equal(mode.HvacHeat)
  // Command was sent, meaning system handled missing target gracefully
}

pub fn handles_completely_unknown_trv_test() {
  // When a TRV has no data at all (both temp and target None),
  // the system should still send a command
  let #(trv_adapter_name, spy) = make_mock_trv_adapter("unknown_trv")

  let assert Ok(started) =
    room_decision_actor.start_with_trv_adapter_name(
      trv_adapter_name: trv_adapter_name,
    )

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  // TRV state with no data at all
  let trv_state =
    room_actor.TrvState(
      temperature: option.None,
      target: option.None,
      mode: mode.HvacHeat,
      is_heating: False,
    )
  let room_state =
    room_actor.RoomState(
      name: "lounge",
      temperature: option.Some(temperature.temperature(20.0)),
      target_temperature: option.Some(temperature.temperature(20.0)),
      house_mode: mode.HouseModeAuto,
      room_mode: mode.RoomModeAuto,
      adjustment: 0.0,
      trv_states: dict.from_list([#(trv_id, trv_state)]),
    )

  process.send(started.data, room_decision_actor.RoomStateChanged(room_state))

  // Should still receive a command
  let cmd =
    test_helpers.expect_receive(spy, 1000, "TRV command for unknown TRV")

  let room_decision_actor.TrvCommand(entity_id, cmd_mode, target) = cmd
  entity_id |> should.equal(trv_id)
  cmd_mode |> should.equal(mode.HvacHeat)
  // Should fall back to room target
  temperature.unwrap(target) |> should.equal(20.0)
}

// =============================================================================
// Offset-based Compensation Tests
// =============================================================================

pub fn offset_formula_accounts_for_trv_temperature_test() {
  // The offset formula: trvTarget = roomTarget + trvTemp - roomTemp
  // This compensates for TRVs that read differently from the room sensor
  //
  // Example: TRV reads 4°C higher than external sensor
  // - Room target: 20°C, Room temp: 18°C, TRV temp: 22°C
  // - Formula: 20 + 22 - 18 = 24°C
  let #(trv_adapter_name, spy) = make_mock_trv_adapter("offset_formula")

  let assert Ok(started) =
    room_decision_actor.start_with_trv_adapter_name(
      trv_adapter_name: trv_adapter_name,
    )

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  let room_state =
    make_room_state_with_trv(
      room_temp: temperature.temperature(18.0),
      target_temp: temperature.temperature(20.0),
      trv_id: trv_id,
      trv_temp: temperature.temperature(22.0),
    )

  process.send(started.data, room_decision_actor.RoomStateChanged(room_state))

  let cmd =
    test_helpers.expect_receive(spy, 1000, "TRV command with offset formula")

  let room_decision_actor.TrvCommand(entity_id, cmd_mode, target) = cmd
  entity_id |> should.equal(trv_id)
  cmd_mode |> should.equal(mode.HvacHeat)
  // Offset formula: 20 + 22 - 18 = 24°C
  // Round up (heating required): 24.0
  temperature.unwrap(target) |> should.equal(24.0)
}

// =============================================================================
// Temperature Clamping Tests
// =============================================================================

pub fn clamps_trv_target_to_minimum_7c_test() {
  // When the offset formula would produce a value below 7°C,
  // the TRV target should be clamped to 7°C (minimum TRV command temperature).
  //
  // Example: Room is already warm, target is low
  // - Room target: 10°C, Room temp: 15°C, TRV temp: 10°C
  // - Formula: 10 + 10 - 15 = 5°C → should be clamped to 7°C
  let #(trv_adapter_name, spy) = make_mock_trv_adapter("clamp_min")

  let assert Ok(started) =
    room_decision_actor.start_with_trv_adapter_name(
      trv_adapter_name: trv_adapter_name,
    )

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  let room_state =
    make_room_state_with_trv(
      room_temp: temperature.temperature(15.0),
      target_temp: temperature.temperature(10.0),
      trv_id: trv_id,
      trv_temp: temperature.temperature(10.0),
    )

  process.send(started.data, room_decision_actor.RoomStateChanged(room_state))

  let cmd =
    test_helpers.expect_receive(spy, 1000, "TRV command clamped to min 7C")

  let room_decision_actor.TrvCommand(entity_id, cmd_mode, target) = cmd
  entity_id |> should.equal(trv_id)
  cmd_mode |> should.equal(mode.HvacHeat)
  // Offset formula: 10 + 10 - 15 = 5°C
  // Should be clamped to minimum: 7°C
  temperature.unwrap(target) |> should.equal(7.0)
}

pub fn clamps_trv_target_to_maximum_32c_test() {
  // When the offset formula would produce a value above 32°C,
  // the TRV target should be clamped to 32°C (maximum TRV command temperature).
  //
  // Example: Cold room with hot TRV reading
  // - Room target: 25°C, Room temp: 15°C, TRV temp: 25°C
  // - Formula: 25 + 25 - 15 = 35°C → should be clamped to 32°C
  let #(trv_adapter_name, spy) = make_mock_trv_adapter("clamp_max")

  let assert Ok(started) =
    room_decision_actor.start_with_trv_adapter_name(
      trv_adapter_name: trv_adapter_name,
    )

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  let room_state =
    make_room_state_with_trv(
      room_temp: temperature.temperature(15.0),
      target_temp: temperature.temperature(25.0),
      trv_id: trv_id,
      trv_temp: temperature.temperature(25.0),
    )

  process.send(started.data, room_decision_actor.RoomStateChanged(room_state))

  let cmd =
    test_helpers.expect_receive(spy, 1000, "TRV command clamped to max 32C")

  let room_decision_actor.TrvCommand(entity_id, cmd_mode, target) = cmd
  entity_id |> should.equal(trv_id)
  cmd_mode |> should.equal(mode.HvacHeat)
  // Offset formula: 25 + 25 - 15 = 35°C
  // Should be clamped to maximum: 32°C
  temperature.unwrap(target) |> should.equal(32.0)
}

// =============================================================================
// TRV Mode Handling Tests
// =============================================================================

pub fn skips_trv_when_mode_is_off_test() {
  // When a TRV is in HvacOff mode, we should NOT send any commands to it.
  // The user has explicitly turned it off; we must respect that.
  let #(trv_adapter_name, spy) = make_mock_trv_adapter("mode_off")

  let assert Ok(started) =
    room_decision_actor.start_with_trv_adapter_name(
      trv_adapter_name: trv_adapter_name,
    )

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  // TRV is OFF - should not receive any commands
  let trv_state =
    room_actor.TrvState(
      temperature: option.Some(temperature.temperature(20.0)),
      target: option.Some(temperature.temperature(20.0)),
      mode: mode.HvacOff,
      is_heating: False,
    )
  let room_state =
    room_actor.RoomState(
      name: "lounge",
      temperature: option.Some(temperature.temperature(20.0)),
      target_temperature: option.Some(temperature.temperature(20.0)),
      house_mode: mode.HouseModeAuto,
      room_mode: mode.RoomModeOff,
      // TRV is off, so room mode is Off
      adjustment: 0.0,
      trv_states: dict.from_list([#(trv_id, trv_state)]),
    )

  process.send(started.data, room_decision_actor.RoomStateChanged(room_state))

  // Give actor time to process
  process.sleep(50)

  // Should NOT receive any command (TRV is off)
  let result = process.receive(spy, 100)
  result |> should.be_error
}

// =============================================================================
// Mode Change Tests - TRV mode auto→heat conversion
// =============================================================================

pub fn sends_mode_change_when_trv_in_auto_mode_test() {
  // When TRV is in HvacAuto mode, we must change it to HvacHeat mode.
  // This matches TypeScript behavior: determineAction returns mode: 'heat'
  // when current mode is 'auto'.
  let #(trv_adapter_name, spy) = make_mock_trv_adapter("auto_mode")

  let assert Ok(started) =
    room_decision_actor.start_with_trv_adapter_name(
      trv_adapter_name: trv_adapter_name,
    )

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  // TRV is in AUTO mode - should receive mode change to HEAT
  let trv_state =
    room_actor.TrvState(
      temperature: option.Some(temperature.temperature(20.0)),
      target: option.Some(temperature.temperature(20.0)),
      mode: mode.HvacAuto,
      is_heating: False,
    )
  let room_state =
    room_actor.RoomState(
      name: "lounge",
      temperature: option.Some(temperature.temperature(20.0)),
      target_temperature: option.Some(temperature.temperature(20.0)),
      house_mode: mode.HouseModeAuto,
      room_mode: mode.RoomModeAuto,
      adjustment: 0.0,
      trv_states: dict.from_list([#(trv_id, trv_state)]),
    )

  process.send(started.data, room_decision_actor.RoomStateChanged(room_state))

  // Should receive command with mode set to Heat
  let cmd =
    test_helpers.expect_receive(spy, 1000, "TRV command for auto->heat mode")

  let room_decision_actor.TrvCommand(entity_id, cmd_mode, target) = cmd
  entity_id |> should.equal(trv_id)
  cmd_mode |> should.equal(mode.HvacHeat)
  temperature.unwrap(target) |> should.equal(20.0)
}

pub fn sends_command_when_mode_changes_from_heat_to_auto_test() {
  // BUG FIX TEST: When TRV mode changes from heat→auto but target stays same,
  // we must still send a command to change it back to heat.
  //
  // Scenario:
  // 1. TRV is in heat mode, target 20°C - we send command
  // 2. User manually changes TRV to auto mode (same target)
  // 3. HA reports TRV in auto mode with target 20°C
  // 4. We MUST send command to change it back to heat
  //
  // The bug was: we only checked if TARGET changed, not if MODE changed.
  let #(trv_adapter_name, spy) = make_mock_trv_adapter("mode_change_heat_auto")

  let assert Ok(started) =
    room_decision_actor.start_with_trv_adapter_name(
      trv_adapter_name: trv_adapter_name,
    )

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  // Step 1: TRV starts in HEAT mode, target 20°C
  let trv_state_heat =
    room_actor.TrvState(
      temperature: option.Some(temperature.temperature(20.0)),
      target: option.Some(temperature.temperature(20.0)),
      mode: mode.HvacHeat,
      is_heating: False,
    )
  let room_state_1 =
    room_actor.RoomState(
      name: "lounge",
      temperature: option.Some(temperature.temperature(20.0)),
      target_temperature: option.Some(temperature.temperature(20.0)),
      house_mode: mode.HouseModeAuto,
      room_mode: mode.RoomModeAuto,
      adjustment: 0.0,
      trv_states: dict.from_list([#(trv_id, trv_state_heat)]),
    )

  // First command - initializes last_sent_targets to 20.0
  process.send(started.data, room_decision_actor.RoomStateChanged(room_state_1))
  let _first_cmd =
    test_helpers.expect_receive(spy, 1000, "First TRV command in mode test")

  // Step 2: User changes TRV to AUTO mode (same target 20°C)
  let trv_state_auto =
    room_actor.TrvState(
      temperature: option.Some(temperature.temperature(20.0)),
      target: option.Some(temperature.temperature(20.0)),
      mode: mode.HvacAuto,
      // Changed from HvacHeat!
      is_heating: False,
    )
  let room_state_2 =
    room_actor.RoomState(
      name: "lounge",
      temperature: option.Some(temperature.temperature(20.0)),
      target_temperature: option.Some(temperature.temperature(20.0)),
      house_mode: mode.HouseModeAuto,
      room_mode: mode.RoomModeAuto,
      adjustment: 0.0,
      trv_states: dict.from_list([#(trv_id, trv_state_auto)]),
    )

  process.send(started.data, room_decision_actor.RoomStateChanged(room_state_2))

  // Step 3: Should receive a SECOND command to change mode back to heat
  // Even though the target is the same (20°C), the mode changed.
  let cmd =
    test_helpers.expect_receive(spy, 1000, "TRV command to restore heat mode")

  let room_decision_actor.TrvCommand(entity_id, cmd_mode, target) = cmd
  entity_id |> should.equal(trv_id)
  cmd_mode |> should.equal(mode.HvacHeat)
  temperature.unwrap(target) |> should.equal(20.0)
}

// =============================================================================
// Temperature Rounding Tests
// =============================================================================

pub fn rounds_up_to_nearest_half_when_heating_required_test() {
  // When heating is required (room_temp < room_target), round UP to nearest 0.5
  // This biases toward more heating (safer - room won't underheat)
  //
  // room_target=20, room_temp=18, trv_temp=21.3
  // Formula: 20 + 21.3 - 18 = 23.3
  // Heating required (18 < 20), so round UP: 23.5
  let #(trv_adapter_name, spy) =
    make_mock_trv_adapter("rounds_up_heating_required")

  let assert Ok(started) =
    room_decision_actor.start_with_trv_adapter_name(
      trv_adapter_name: trv_adapter_name,
    )

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  let room_state =
    make_room_state_with_trv(
      room_temp: temperature.temperature(18.0),
      target_temp: temperature.temperature(20.0),
      trv_id: trv_id,
      trv_temp: temperature.temperature(21.3),
    )

  process.send(started.data, room_decision_actor.RoomStateChanged(room_state))

  let cmd = test_helpers.expect_receive(spy, 1000, "TRV command rounded up")

  let room_decision_actor.TrvCommand(entity_id, _cmd_mode, target) = cmd
  entity_id |> should.equal(trv_id)
  // 20 + 21.3 - 18 = 23.3, round UP to 23.5
  temperature.unwrap(target) |> should.equal(23.5)
}

pub fn rounds_down_to_nearest_half_when_not_heating_test() {
  // When heating is NOT required (room_temp >= room_target), round DOWN to nearest 0.5
  // This prevents overshooting the target
  //
  // room_target=20, room_temp=21, trv_temp=20.3
  // Formula: 20 + 20.3 - 21 = 19.3
  // NOT heating required (21 >= 20), so round DOWN: 19.0
  let #(trv_adapter_name, spy) =
    make_mock_trv_adapter("rounds_down_not_heating")

  let assert Ok(started) =
    room_decision_actor.start_with_trv_adapter_name(
      trv_adapter_name: trv_adapter_name,
    )

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  let room_state =
    make_room_state_with_trv(
      room_temp: temperature.temperature(21.0),
      target_temp: temperature.temperature(20.0),
      trv_id: trv_id,
      trv_temp: temperature.temperature(20.3),
    )

  process.send(started.data, room_decision_actor.RoomStateChanged(room_state))

  let cmd = test_helpers.expect_receive(spy, 1000, "TRV command rounded down")

  let room_decision_actor.TrvCommand(entity_id, _cmd_mode, target) = cmd
  entity_id |> should.equal(trv_id)
  // 20 + 20.3 - 21 = 19.3, round DOWN to 19.0
  temperature.unwrap(target) |> should.equal(19.0)
}

pub fn rounds_up_when_room_exactly_at_target_but_needs_heating_test() {
  // Edge case: room is exactly at target (20°C), but TRV reads higher
  // Formula produces non-half value. Since room_temp == room_target,
  // heating is NOT required, so round DOWN.
  //
  // room_target=20, room_temp=20, trv_temp=20.7
  // Formula: 20 + 20.7 - 20 = 20.7
  // NOT heating required (20 >= 20), so round DOWN: 20.5
  let #(trv_adapter_name, spy) = make_mock_trv_adapter("rounds_at_target")

  let assert Ok(started) =
    room_decision_actor.start_with_trv_adapter_name(
      trv_adapter_name: trv_adapter_name,
    )

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  let room_state =
    make_room_state_with_trv(
      room_temp: temperature.temperature(20.0),
      target_temp: temperature.temperature(20.0),
      trv_id: trv_id,
      trv_temp: temperature.temperature(20.7),
    )

  process.send(started.data, room_decision_actor.RoomStateChanged(room_state))

  let cmd =
    test_helpers.expect_receive(spy, 1000, "TRV command at exact target")

  let room_decision_actor.TrvCommand(entity_id, _cmd_mode, target) = cmd
  entity_id |> should.equal(trv_id)
  // 20 + 20.7 - 20 = 20.7, NOT heating (20 >= 20), round DOWN: 20.5
  temperature.unwrap(target) |> should.equal(20.5)
}

pub fn rounding_applies_after_clamping_test() {
  // Verify that rounding happens AFTER clamping, matching TypeScript behaviour.
  // If the unclamped value would be clamped, the clamped value should be rounded.
  //
  // room_target=25, room_temp=14, trv_temp=25
  // Formula: 25 + 25 - 14 = 36 → clamp to 32
  // Heating required (14 < 25), but 32.0 is already on 0.5 boundary
  let #(trv_adapter_name, spy) = make_mock_trv_adapter("rounding_after_clamp")

  let assert Ok(started) =
    room_decision_actor.start_with_trv_adapter_name(
      trv_adapter_name: trv_adapter_name,
    )

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  let room_state =
    make_room_state_with_trv(
      room_temp: temperature.temperature(14.0),
      target_temp: temperature.temperature(25.0),
      trv_id: trv_id,
      trv_temp: temperature.temperature(25.0),
    )

  process.send(started.data, room_decision_actor.RoomStateChanged(room_state))

  let cmd = test_helpers.expect_receive(spy, 1000, "TRV command after clamping")

  let room_decision_actor.TrvCommand(entity_id, _cmd_mode, target) = cmd
  entity_id |> should.equal(trv_id)
  // 36 clamped to 32, then 32 rounded stays 32
  temperature.unwrap(target) |> should.equal(32.0)
}

// =============================================================================
// HA State Comparison Tests - compare against HA-reported state, not last-sent
// =============================================================================

pub fn resends_command_when_ha_reports_different_target_test() {
  // BUG FIX: Compare against HA-reported target, not last-sent target.
  // This matches TypeScript behaviour: keeps retrying until HA confirms the value.
  //
  // Scenario:
  // 1. Room wants 22°C, TRV reports target 20°C (from HA)
  // 2. We send command to set TRV to 22°C
  // 3. Command fails (TRV offline, timeout, etc.)
  // 4. HA still reports TRV target as 20°C
  // 5. Room state update arrives again (same desired target 22°C)
  // 6. We MUST resend command because HA target (20°C) != desired (22°C)
  //
  // Current bug: compares against last_sent_targets (22°C == 22°C → no resend)
  // Correct: compares against HA state (20°C != 22°C → resend)
  let #(trv_adapter_name, spy) = make_mock_trv_adapter("ha_reports_different")

  let assert Ok(started) =
    room_decision_actor.start_with_trv_adapter_name(
      trv_adapter_name: trv_adapter_name,
    )

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  // Step 1: Room at 20°C wants 22°C, TRV reports target 20°C (HA state)
  // Formula: 22 + 20 - 20 = 22°C
  let trv_state_1 =
    room_actor.TrvState(
      temperature: option.Some(temperature.temperature(20.0)),
      target: option.Some(temperature.temperature(20.0)),
      // HA reports 20°C
      mode: mode.HvacHeat,
      is_heating: False,
    )
  let room_state_1 =
    room_actor.RoomState(
      name: "lounge",
      temperature: option.Some(temperature.temperature(20.0)),
      target_temperature: option.Some(temperature.temperature(22.0)),
      // Want 22°C
      house_mode: mode.HouseModeAuto,
      room_mode: mode.RoomModeAuto,
      adjustment: 0.0,
      trv_states: dict.from_list([#(trv_id, trv_state_1)]),
    )

  // First command - should send 22°C
  process.send(started.data, room_decision_actor.RoomStateChanged(room_state_1))
  let cmd1 =
    test_helpers.expect_receive(spy, 1000, "First TRV command to set 22C")

  let room_decision_actor.TrvCommand(_, _, target1) = cmd1
  temperature.unwrap(target1) |> should.equal(22.0)

  // Step 2: HA STILL reports target 20°C (command failed/wasn't applied)
  // Same room state arrives again - HA target still 20°C
  process.send(started.data, room_decision_actor.RoomStateChanged(room_state_1))

  // Step 3: Should resend command because HA target (20°C) != desired (22°C)
  let cmd2 =
    test_helpers.expect_receive(spy, 1000, "Resent TRV command (HA mismatch)")

  let room_decision_actor.TrvCommand(entity_id2, cmd_mode2, target2) = cmd2
  entity_id2 |> should.equal(trv_id)
  cmd_mode2 |> should.equal(mode.HvacHeat)
  // Should resend 22°C because HA still shows 20°C
  temperature.unwrap(target2) |> should.equal(22.0)
}

pub fn stops_sending_when_ha_confirms_target_test() {
  // Verify we stop sending commands once HA confirms the target we wanted.
  //
  // Scenario:
  // 1. Room wants 22°C, TRV reports target 20°C
  // 2. We send command to set TRV to 22°C
  // 3. HA updates - TRV target now 22°C (command succeeded!)
  // 4. Room state update arrives with same desired target
  // 5. Should NOT resend command because HA target (22°C) == desired (22°C)
  let #(trv_adapter_name, spy) = make_mock_trv_adapter("ha_confirms_target")

  let assert Ok(started) =
    room_decision_actor.start_with_trv_adapter_name(
      trv_adapter_name: trv_adapter_name,
    )

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  // Step 1: TRV reports target 20°C, we want 22°C
  let trv_state_before =
    room_actor.TrvState(
      temperature: option.Some(temperature.temperature(20.0)),
      target: option.Some(temperature.temperature(20.0)),
      // HA reports 20°C
      mode: mode.HvacHeat,
      is_heating: False,
    )
  let room_state_before =
    room_actor.RoomState(
      name: "lounge",
      temperature: option.Some(temperature.temperature(20.0)),
      target_temperature: option.Some(temperature.temperature(22.0)),
      house_mode: mode.HouseModeAuto,
      room_mode: mode.RoomModeAuto,
      adjustment: 0.0,
      trv_states: dict.from_list([#(trv_id, trv_state_before)]),
    )

  process.send(
    started.data,
    room_decision_actor.RoomStateChanged(room_state_before),
  )
  let _cmd1 =
    test_helpers.expect_receive(spy, 1000, "Initial TRV command before confirm")

  // Step 2: HA now reports target 22°C (command succeeded)
  let trv_state_after =
    room_actor.TrvState(
      temperature: option.Some(temperature.temperature(20.0)),
      target: option.Some(temperature.temperature(22.0)),
      // HA now reports 22°C!
      mode: mode.HvacHeat,
      is_heating: False,
    )
  let room_state_after =
    room_actor.RoomState(
      name: "lounge",
      temperature: option.Some(temperature.temperature(20.0)),
      target_temperature: option.Some(temperature.temperature(22.0)),
      // Still want 22°C
      house_mode: mode.HouseModeAuto,
      room_mode: mode.RoomModeAuto,
      adjustment: 0.0,
      trv_states: dict.from_list([#(trv_id, trv_state_after)]),
    )

  process.send(
    started.data,
    room_decision_actor.RoomStateChanged(room_state_after),
  )

  // Give actor time to process
  process.sleep(50)

  // Should NOT receive another command - HA confirmed the target
  let result = process.receive(spy, 100)
  result |> should.be_error
}

pub fn corrects_manual_trv_changes_test() {
  // When user manually changes TRV target in Home Assistant,
  // the system should correct it to the desired value.
  //
  // Scenario:
  // 1. System sets TRV to 22°C, HA confirms
  // 2. User manually changes TRV to 18°C via HA UI
  // 3. HA reports new target 18°C
  // 4. System should send command to restore 22°C
  let #(trv_adapter_name, spy) = make_mock_trv_adapter("corrects_manual")

  let assert Ok(started) =
    room_decision_actor.start_with_trv_adapter_name(
      trv_adapter_name: trv_adapter_name,
    )

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  // Step 1: TRV at 22°C (matches what we want)
  let trv_state_correct =
    room_actor.TrvState(
      temperature: option.Some(temperature.temperature(20.0)),
      target: option.Some(temperature.temperature(22.0)),
      mode: mode.HvacHeat,
      is_heating: False,
    )
  let room_state_correct =
    room_actor.RoomState(
      name: "lounge",
      temperature: option.Some(temperature.temperature(20.0)),
      target_temperature: option.Some(temperature.temperature(22.0)),
      house_mode: mode.HouseModeAuto,
      room_mode: mode.RoomModeAuto,
      adjustment: 0.0,
      trv_states: dict.from_list([#(trv_id, trv_state_correct)]),
    )

  // Initial state - sends command (first time seeing this TRV)
  process.send(
    started.data,
    room_decision_actor.RoomStateChanged(room_state_correct),
  )
  let _initial =
    test_helpers.expect_receive(spy, 1000, "Initial TRV command (correct)")

  // Step 2: User manually changes TRV to 18°C
  let trv_state_manual =
    room_actor.TrvState(
      temperature: option.Some(temperature.temperature(20.0)),
      target: option.Some(temperature.temperature(18.0)),
      // User changed to 18°C!
      mode: mode.HvacHeat,
      is_heating: False,
    )
  let room_state_manual =
    room_actor.RoomState(
      name: "lounge",
      temperature: option.Some(temperature.temperature(20.0)),
      target_temperature: option.Some(temperature.temperature(22.0)),
      // Still want 22°C
      house_mode: mode.HouseModeAuto,
      room_mode: mode.RoomModeAuto,
      adjustment: 0.0,
      trv_states: dict.from_list([#(trv_id, trv_state_manual)]),
    )

  process.send(
    started.data,
    room_decision_actor.RoomStateChanged(room_state_manual),
  )

  // Should send command to correct back to 22°C
  let cmd =
    test_helpers.expect_receive(spy, 1000, "TRV command correcting manual")

  let room_decision_actor.TrvCommand(entity_id, cmd_mode, target) = cmd
  entity_id |> should.equal(trv_id)
  cmd_mode |> should.equal(mode.HvacHeat)
  temperature.unwrap(target) |> should.equal(22.0)
}
