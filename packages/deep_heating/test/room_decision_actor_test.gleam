import deep_heating/rooms/room_actor
import deep_heating/rooms/room_decision_actor
import deep_heating/entity_id
import deep_heating/mode
import deep_heating/temperature
import gleam/dict
import gleam/erlang/process
import gleam/list
import gleam/option
import gleeunit/should

// =============================================================================
// Test Helpers
// =============================================================================

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
  // Create a subject to receive TRV commands
  let trv_commands = process.new_subject()

  // Decision actor should start successfully
  let result =
    room_decision_actor.start_with_trv_commands(trv_commands: trv_commands)
  should.be_ok(result)
}

// =============================================================================
// Target Computation Tests
// =============================================================================

pub fn sends_room_target_when_room_at_temperature_test() {
  // When room is at target temperature (within 0.5°C tolerance),
  // TRV should be set to the room target directly (no compensation)
  let trv_commands: process.Subject(room_decision_actor.TrvCommand) =
    process.new_subject()

  let assert Ok(started) =
    room_decision_actor.start_with_trv_commands(trv_commands: trv_commands)

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
  let assert Ok(cmd) = process.receive(trv_commands, 1000)

  let room_decision_actor.TrvCommand(entity_id, cmd_mode, target) = cmd
  entity_id |> should.equal(trv_id)
  cmd_mode |> should.equal(mode.HvacHeat)
  temperature.unwrap(target) |> should.equal(20.0)
}

pub fn pushes_trv_target_higher_when_room_is_cold_test() {
  // When room is cold, offset formula pushes TRV higher to compensate
  // Formula: trvTarget = roomTarget + trvTemp - roomTemp
  let trv_commands: process.Subject(room_decision_actor.TrvCommand) =
    process.new_subject()

  let assert Ok(started) =
    room_decision_actor.start_with_trv_commands(trv_commands: trv_commands)

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

  let assert Ok(cmd) = process.receive(trv_commands, 1000)

  let room_decision_actor.TrvCommand(entity_id, cmd_mode, target) = cmd
  entity_id |> should.equal(trv_id)
  cmd_mode |> should.equal(mode.HvacHeat)
  // Offset formula: 20 + 20 - 19 = 21
  temperature.unwrap(target) |> should.equal(21.0)
}

pub fn backs_off_trv_when_room_is_hot_test() {
  // When room is hot, offset formula backs off TRV
  // Formula: trvTarget = roomTarget + trvTemp - roomTemp
  let trv_commands: process.Subject(room_decision_actor.TrvCommand) =
    process.new_subject()

  let assert Ok(started) =
    room_decision_actor.start_with_trv_commands(trv_commands: trv_commands)

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

  let assert Ok(cmd) = process.receive(trv_commands, 1000)

  let room_decision_actor.TrvCommand(entity_id, cmd_mode, target) = cmd
  entity_id |> should.equal(trv_id)
  cmd_mode |> should.equal(mode.HvacHeat)
  // Offset formula: 20 + 20 - 21 = 19
  temperature.unwrap(target) |> should.equal(19.0)
}

pub fn uses_room_target_when_no_external_sensor_test() {
  // When there's no external temperature sensor, use the room target directly
  // (no compensation possible without knowing actual room temp)
  let trv_commands: process.Subject(room_decision_actor.TrvCommand) =
    process.new_subject()

  let assert Ok(started) =
    room_decision_actor.start_with_trv_commands(trv_commands: trv_commands)

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

  let assert Ok(cmd) = process.receive(trv_commands, 1000)

  let room_decision_actor.TrvCommand(entity_id, cmd_mode, target) = cmd
  entity_id |> should.equal(trv_id)
  cmd_mode |> should.equal(mode.HvacHeat)
  // Should just use the room target directly
  temperature.unwrap(target) |> should.equal(20.0)
}

pub fn only_sends_command_when_target_differs_test() {
  // Should not send duplicate commands when computed target hasn't changed
  let trv_commands: process.Subject(room_decision_actor.TrvCommand) =
    process.new_subject()

  let assert Ok(started) =
    room_decision_actor.start_with_trv_commands(trv_commands: trv_commands)

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
  let assert Ok(_cmd) = process.receive(trv_commands, 1000)

  // Second update with same state - should NOT send command
  process.send(started.data, room_decision_actor.RoomStateChanged(room_state))

  // Give actor time to process
  process.sleep(50)

  // Should NOT receive a second command (timeout expected)
  let result = process.receive(trv_commands, 100)
  result |> should.be_error
}

pub fn handles_multiple_trvs_in_room_test() {
  // When a room has multiple TRVs, all should receive SetTarget commands
  let trv_commands: process.Subject(room_decision_actor.TrvCommand) =
    process.new_subject()

  let assert Ok(started) =
    room_decision_actor.start_with_trv_commands(trv_commands: trv_commands)

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
  let assert Ok(cmd1) = process.receive(trv_commands, 1000)
  let assert Ok(cmd2) = process.receive(trv_commands, 1000)

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
  let trv_commands: process.Subject(room_decision_actor.TrvCommand) =
    process.new_subject()

  let assert Ok(started) =
    room_decision_actor.start_with_trv_commands(trv_commands: trv_commands)

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
  let assert Ok(cmd) = process.receive(trv_commands, 1000)

  let room_decision_actor.TrvCommand(entity_id, cmd_mode, target) = cmd
  entity_id |> should.equal(trv_id)
  cmd_mode |> should.equal(mode.HvacHeat)
  // With no TRV temp data, should use room target directly
  temperature.unwrap(target) |> should.equal(20.0)
}

pub fn handles_trv_with_missing_target_test() {
  // When a TRV has no current target, the system should still compute and send one
  let trv_commands: process.Subject(room_decision_actor.TrvCommand) =
    process.new_subject()

  let assert Ok(started) =
    room_decision_actor.start_with_trv_commands(trv_commands: trv_commands)

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
  let assert Ok(cmd) = process.receive(trv_commands, 1000)

  let room_decision_actor.TrvCommand(entity_id, cmd_mode, _target) = cmd
  entity_id |> should.equal(trv_id)
  cmd_mode |> should.equal(mode.HvacHeat)
  // Command was sent, meaning system handled missing target gracefully
}

pub fn handles_completely_unknown_trv_test() {
  // When a TRV has no data at all (both temp and target None),
  // the system should still send a command
  let trv_commands: process.Subject(room_decision_actor.TrvCommand) =
    process.new_subject()

  let assert Ok(started) =
    room_decision_actor.start_with_trv_commands(trv_commands: trv_commands)

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
  let assert Ok(cmd) = process.receive(trv_commands, 1000)

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
  let trv_commands: process.Subject(room_decision_actor.TrvCommand) =
    process.new_subject()

  let assert Ok(started) =
    room_decision_actor.start_with_trv_commands(trv_commands: trv_commands)

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  let room_state =
    make_room_state_with_trv(
      room_temp: temperature.temperature(18.0),
      target_temp: temperature.temperature(20.0),
      trv_id: trv_id,
      trv_temp: temperature.temperature(22.0),
    )

  process.send(started.data, room_decision_actor.RoomStateChanged(room_state))

  let assert Ok(cmd) = process.receive(trv_commands, 1000)

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
  let trv_commands: process.Subject(room_decision_actor.TrvCommand) =
    process.new_subject()

  let assert Ok(started) =
    room_decision_actor.start_with_trv_commands(trv_commands: trv_commands)

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  let room_state =
    make_room_state_with_trv(
      room_temp: temperature.temperature(15.0),
      target_temp: temperature.temperature(10.0),
      trv_id: trv_id,
      trv_temp: temperature.temperature(10.0),
    )

  process.send(started.data, room_decision_actor.RoomStateChanged(room_state))

  let assert Ok(cmd) = process.receive(trv_commands, 1000)

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
  let trv_commands: process.Subject(room_decision_actor.TrvCommand) =
    process.new_subject()

  let assert Ok(started) =
    room_decision_actor.start_with_trv_commands(trv_commands: trv_commands)

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  let room_state =
    make_room_state_with_trv(
      room_temp: temperature.temperature(15.0),
      target_temp: temperature.temperature(25.0),
      trv_id: trv_id,
      trv_temp: temperature.temperature(25.0),
    )

  process.send(started.data, room_decision_actor.RoomStateChanged(room_state))

  let assert Ok(cmd) = process.receive(trv_commands, 1000)

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
  let trv_commands: process.Subject(room_decision_actor.TrvCommand) =
    process.new_subject()

  let assert Ok(started) =
    room_decision_actor.start_with_trv_commands(trv_commands: trv_commands)

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
  let result = process.receive(trv_commands, 100)
  result |> should.be_error
}

// =============================================================================
// Mode Change Tests - TRV mode auto→heat conversion
// =============================================================================

pub fn sends_mode_change_when_trv_in_auto_mode_test() {
  // When TRV is in HvacAuto mode, we must change it to HvacHeat mode.
  // This matches TypeScript behavior: determineAction returns mode: 'heat'
  // when current mode is 'auto'.
  let trv_commands: process.Subject(room_decision_actor.TrvCommand) =
    process.new_subject()

  let assert Ok(started) =
    room_decision_actor.start_with_trv_commands(trv_commands: trv_commands)

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
  let assert Ok(cmd) = process.receive(trv_commands, 1000)

  let room_decision_actor.TrvCommand(entity_id, cmd_mode, target) = cmd
  entity_id |> should.equal(trv_id)
  cmd_mode |> should.equal(mode.HvacHeat)
  temperature.unwrap(target) |> should.equal(20.0)
}
