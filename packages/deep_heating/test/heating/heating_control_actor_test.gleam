import deep_heating/entity_id
import deep_heating/heating/heating_control_actor
import deep_heating/mode
import deep_heating/rooms/room_actor
import deep_heating/temperature
import gleam/dict
import gleam/erlang/process
import gleam/option
import gleeunit/should

// =============================================================================
// Test Helpers
// =============================================================================

fn make_boiler_entity_id() -> entity_id.ClimateEntityId {
  let assert Ok(id) = entity_id.climate_entity_id("climate.heating")
  id
}

fn make_room_state(
  name name: String,
  temp temp: Float,
  target target: Float,
) -> room_actor.RoomState {
  room_actor.RoomState(
    name: name,
    temperature: option.Some(temperature.temperature(temp)),
    target_temperature: option.Some(temperature.temperature(target)),
    house_mode: mode.HouseModeAuto,
    room_mode: mode.RoomModeAuto,
    adjustment: 0.0,
    trv_states: dict.new(),
  )
}

fn make_cold_room(name: String) -> room_actor.RoomState {
  // Room at 18°C with target 21°C - needs heating
  make_room_state(name, 18.0, 21.0)
}

fn make_warm_room(name: String) -> room_actor.RoomState {
  // Room at 22°C with target 21°C - doesn't need heating
  make_room_state(name, 22.0, 21.0)
}

// =============================================================================
// Boiler Turn On Tests
// =============================================================================

pub fn heating_control_actor_starts_successfully_test() {
  let boiler_commands: process.Subject(heating_control_actor.BoilerCommand) =
    process.new_subject()

  let result =
    heating_control_actor.start(
      boiler_entity_id: make_boiler_entity_id(),
      boiler_commands: boiler_commands,
    )

  should.be_ok(result)
}

pub fn heating_control_actor_turns_boiler_on_when_room_needs_heating_test() {
  let boiler_commands: process.Subject(heating_control_actor.BoilerCommand) =
    process.new_subject()

  let assert Ok(started) =
    heating_control_actor.start(
      boiler_entity_id: make_boiler_entity_id(),
      boiler_commands: boiler_commands,
    )

  // Tell it the boiler is currently off
  process.send(started.data, heating_control_actor.BoilerStatusChanged(False))
  process.sleep(10)

  // Send a room state that needs heating (temp < target)
  let cold_room = make_cold_room("lounge")
  process.send(
    started.data,
    heating_control_actor.RoomUpdated("lounge", cold_room),
  )

  // Should receive a command to turn boiler on
  let assert Ok(msg) = process.receive(boiler_commands, 1000)
  case msg {
    heating_control_actor.BoilerCommand(entity_id, hvac_mode, _target) -> {
      entity_id |> should.equal(make_boiler_entity_id())
      hvac_mode |> should.equal(mode.HvacHeat)
    }
  }
}

pub fn heating_control_actor_does_not_turn_boiler_on_when_already_on_test() {
  let boiler_commands: process.Subject(heating_control_actor.BoilerCommand) =
    process.new_subject()

  let assert Ok(started) =
    heating_control_actor.start(
      boiler_entity_id: make_boiler_entity_id(),
      boiler_commands: boiler_commands,
    )

  // Tell it the boiler is currently ON
  process.send(started.data, heating_control_actor.BoilerStatusChanged(True))
  process.sleep(10)

  // Send a room state that needs heating
  let cold_room = make_cold_room("lounge")
  process.send(
    started.data,
    heating_control_actor.RoomUpdated("lounge", cold_room),
  )
  process.sleep(50)

  // Should NOT receive any command (boiler already on)
  let result = process.receive(boiler_commands, 100)
  result |> should.be_error
}

// =============================================================================
// Boiler Turn Off Tests
// =============================================================================

pub fn heating_control_actor_turns_boiler_off_when_no_rooms_need_heating_test() {
  let boiler_commands: process.Subject(heating_control_actor.BoilerCommand) =
    process.new_subject()

  let assert Ok(started) =
    heating_control_actor.start(
      boiler_entity_id: make_boiler_entity_id(),
      boiler_commands: boiler_commands,
    )

  // Tell it the boiler is currently ON
  process.send(started.data, heating_control_actor.BoilerStatusChanged(True))
  process.sleep(10)

  // Send a room state that does NOT need heating (temp >= target)
  let warm_room = make_warm_room("lounge")
  process.send(
    started.data,
    heating_control_actor.RoomUpdated("lounge", warm_room),
  )

  // Should receive a command to turn boiler off
  let assert Ok(msg) = process.receive(boiler_commands, 1000)
  case msg {
    heating_control_actor.BoilerCommand(entity_id, hvac_mode, _target) -> {
      entity_id |> should.equal(make_boiler_entity_id())
      hvac_mode |> should.equal(mode.HvacOff)
    }
  }
}

pub fn heating_control_actor_does_not_turn_boiler_off_when_already_off_test() {
  let boiler_commands: process.Subject(heating_control_actor.BoilerCommand) =
    process.new_subject()

  let assert Ok(started) =
    heating_control_actor.start(
      boiler_entity_id: make_boiler_entity_id(),
      boiler_commands: boiler_commands,
    )

  // Tell it the boiler is currently OFF
  process.send(started.data, heating_control_actor.BoilerStatusChanged(False))
  process.sleep(10)

  // Send a warm room (no heating needed) - but we need to send a cold room first
  // to establish the room exists, then warm it up
  let warm_room = make_warm_room("lounge")
  process.send(
    started.data,
    heating_control_actor.RoomUpdated("lounge", warm_room),
  )
  process.sleep(50)

  // Should NOT receive any command (boiler already off)
  let result = process.receive(boiler_commands, 100)
  result |> should.be_error
}

// =============================================================================
// Multiple Rooms Tests
// =============================================================================

pub fn heating_control_actor_keeps_boiler_on_if_any_room_needs_heating_test() {
  let boiler_commands: process.Subject(heating_control_actor.BoilerCommand) =
    process.new_subject()

  let assert Ok(started) =
    heating_control_actor.start(
      boiler_entity_id: make_boiler_entity_id(),
      boiler_commands: boiler_commands,
    )

  // Tell it the boiler is currently ON
  process.send(started.data, heating_control_actor.BoilerStatusChanged(True))
  process.sleep(10)

  // Add a cold room
  let cold_room = make_cold_room("bedroom")
  process.send(
    started.data,
    heating_control_actor.RoomUpdated("bedroom", cold_room),
  )
  process.sleep(10)

  // Add a warm room (lounge is warm, but bedroom still needs heating)
  let warm_room = make_warm_room("lounge")
  process.send(
    started.data,
    heating_control_actor.RoomUpdated("lounge", warm_room),
  )
  process.sleep(50)

  // Should NOT receive any off command (bedroom still needs heating)
  let result = process.receive(boiler_commands, 100)
  result |> should.be_error
}

// =============================================================================
// GetState Tests
// =============================================================================

pub fn heating_control_actor_returns_initial_state_test() {
  let boiler_commands: process.Subject(heating_control_actor.BoilerCommand) =
    process.new_subject()

  let assert Ok(started) =
    heating_control_actor.start(
      boiler_entity_id: make_boiler_entity_id(),
      boiler_commands: boiler_commands,
    )

  // Query the state
  let reply_subject = process.new_subject()
  process.send(started.data, heating_control_actor.GetState(reply_subject))

  let assert Ok(state) = process.receive(reply_subject, 1000)

  // Initial state should have boiler off and no rooms
  state.boiler_is_heating |> should.be_false
  dict.size(state.room_states) |> should.equal(0)
}

pub fn heating_control_actor_get_state_reflects_boiler_status_test() {
  let boiler_commands: process.Subject(heating_control_actor.BoilerCommand) =
    process.new_subject()

  let assert Ok(started) =
    heating_control_actor.start(
      boiler_entity_id: make_boiler_entity_id(),
      boiler_commands: boiler_commands,
    )

  // Tell it the boiler is on
  process.send(started.data, heating_control_actor.BoilerStatusChanged(True))
  process.sleep(10)

  // Query the state
  let reply_subject = process.new_subject()
  process.send(started.data, heating_control_actor.GetState(reply_subject))

  let assert Ok(state) = process.receive(reply_subject, 1000)

  // State should reflect boiler is on
  state.boiler_is_heating |> should.be_true
}

pub fn heating_control_actor_get_state_reflects_room_states_test() {
  let boiler_commands: process.Subject(heating_control_actor.BoilerCommand) =
    process.new_subject()

  let assert Ok(started) =
    heating_control_actor.start(
      boiler_entity_id: make_boiler_entity_id(),
      boiler_commands: boiler_commands,
    )

  // Add two rooms
  let cold_room = make_cold_room("lounge")
  let warm_room = make_warm_room("bedroom")
  process.send(
    started.data,
    heating_control_actor.RoomUpdated("lounge", cold_room),
  )
  process.send(
    started.data,
    heating_control_actor.RoomUpdated("bedroom", warm_room),
  )
  process.sleep(10)

  // Query the state
  let reply_subject = process.new_subject()
  process.send(started.data, heating_control_actor.GetState(reply_subject))

  let assert Ok(state) = process.receive(reply_subject, 1000)

  // State should have both rooms
  dict.size(state.room_states) |> should.equal(2)
  let assert Ok(lounge_state) = dict.get(state.room_states, "lounge")
  lounge_state.name |> should.equal("lounge")
}
