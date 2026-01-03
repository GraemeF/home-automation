import deep_heating/actor/room_actor
import deep_heating/actor/room_decision_actor
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
    )
  room_actor.RoomState(
    name: "lounge",
    temperature: option.Some(room_temp),
    target_temperature: option.Some(target_temp),
    house_mode: mode.HouseModeAuto,
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
  let result = room_decision_actor.start(trv_commands: trv_commands)
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

  let assert Ok(started) = room_decision_actor.start(trv_commands: trv_commands)

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

  case cmd {
    room_decision_actor.SetTrvTarget(entity_id, target) -> {
      entity_id |> should.equal(trv_id)
      temperature.unwrap(target) |> should.equal(20.0)
    }
  }
}

pub fn pushes_trv_target_higher_when_room_is_cold_test() {
  // When room is more than 0.5°C below target, push TRV 2°C higher
  // to compensate for heat loss
  let trv_commands: process.Subject(room_decision_actor.TrvCommand) =
    process.new_subject()

  let assert Ok(started) = room_decision_actor.start(trv_commands: trv_commands)

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  // Room at 19°C, target 20°C (diff = 1°C > 0.5) - TRV should be set to 22°C
  let room_state =
    make_room_state_with_trv(
      room_temp: temperature.temperature(19.0),
      target_temp: temperature.temperature(20.0),
      trv_id: trv_id,
      trv_temp: temperature.temperature(20.0),
    )

  process.send(started.data, room_decision_actor.RoomStateChanged(room_state))

  let assert Ok(cmd) = process.receive(trv_commands, 1000)

  case cmd {
    room_decision_actor.SetTrvTarget(entity_id, target) -> {
      entity_id |> should.equal(trv_id)
      // Should be room target (20) + 2 = 22
      temperature.unwrap(target) |> should.equal(22.0)
    }
  }
}

pub fn backs_off_trv_when_room_is_hot_test() {
  // When room is more than 0.5°C above target, back off TRV by 1°C
  let trv_commands: process.Subject(room_decision_actor.TrvCommand) =
    process.new_subject()

  let assert Ok(started) = room_decision_actor.start(trv_commands: trv_commands)

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  // Room at 21°C, target 20°C (diff = -1°C < -0.5) - TRV should be set to 19°C
  let room_state =
    make_room_state_with_trv(
      room_temp: temperature.temperature(21.0),
      target_temp: temperature.temperature(20.0),
      trv_id: trv_id,
      trv_temp: temperature.temperature(20.0),
    )

  process.send(started.data, room_decision_actor.RoomStateChanged(room_state))

  let assert Ok(cmd) = process.receive(trv_commands, 1000)

  case cmd {
    room_decision_actor.SetTrvTarget(entity_id, target) -> {
      entity_id |> should.equal(trv_id)
      // Should be room target (20) - 1 = 19
      temperature.unwrap(target) |> should.equal(19.0)
    }
  }
}

pub fn uses_room_target_when_no_external_sensor_test() {
  // When there's no external temperature sensor, use the room target directly
  // (no compensation possible without knowing actual room temp)
  let trv_commands: process.Subject(room_decision_actor.TrvCommand) =
    process.new_subject()

  let assert Ok(started) = room_decision_actor.start(trv_commands: trv_commands)

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  // Room state with no external temperature sensor
  let trv_state =
    room_actor.TrvState(
      temperature: option.Some(temperature.temperature(20.0)),
      target: option.Some(temperature.temperature(20.0)),
    )
  let room_state =
    room_actor.RoomState(
      name: "lounge",
      temperature: option.None,
      // No external sensor!
      target_temperature: option.Some(temperature.temperature(20.0)),
      house_mode: mode.HouseModeAuto,
      adjustment: 0.0,
      trv_states: dict.from_list([#(trv_id, trv_state)]),
    )

  process.send(started.data, room_decision_actor.RoomStateChanged(room_state))

  let assert Ok(cmd) = process.receive(trv_commands, 1000)

  case cmd {
    room_decision_actor.SetTrvTarget(entity_id, target) -> {
      entity_id |> should.equal(trv_id)
      // Should just use the room target directly
      temperature.unwrap(target) |> should.equal(20.0)
    }
  }
}

pub fn only_sends_command_when_target_differs_test() {
  // Should not send duplicate commands when computed target hasn't changed
  let trv_commands: process.Subject(room_decision_actor.TrvCommand) =
    process.new_subject()

  let assert Ok(started) = room_decision_actor.start(trv_commands: trv_commands)

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

  let assert Ok(started) = room_decision_actor.start(trv_commands: trv_commands)

  let assert Ok(trv1) = entity_id.climate_entity_id("climate.bedroom_trv_1")
  let assert Ok(trv2) = entity_id.climate_entity_id("climate.bedroom_trv_2")

  // Room state with two TRVs
  let trv_state1 =
    room_actor.TrvState(
      temperature: option.Some(temperature.temperature(20.0)),
      target: option.Some(temperature.temperature(20.0)),
    )
  let trv_state2 =
    room_actor.TrvState(
      temperature: option.Some(temperature.temperature(19.5)),
      target: option.Some(temperature.temperature(20.0)),
    )
  let room_state =
    room_actor.RoomState(
      name: "bedroom",
      temperature: option.Some(temperature.temperature(20.0)),
      target_temperature: option.Some(temperature.temperature(20.0)),
      house_mode: mode.HouseModeAuto,
      adjustment: 0.0,
      trv_states: dict.from_list([#(trv1, trv_state1), #(trv2, trv_state2)]),
    )

  process.send(started.data, room_decision_actor.RoomStateChanged(room_state))

  // Should receive two commands - one for each TRV
  let assert Ok(cmd1) = process.receive(trv_commands, 1000)
  let assert Ok(cmd2) = process.receive(trv_commands, 1000)

  // Collect the entity IDs that received commands
  let ids = case cmd1, cmd2 {
    room_decision_actor.SetTrvTarget(id1, _),
      room_decision_actor.SetTrvTarget(id2, _)
    -> [id1, id2]
  }

  // Both TRVs should have received commands (order may vary)
  list.contains(ids, trv1) |> should.be_true
  list.contains(ids, trv2) |> should.be_true
}
