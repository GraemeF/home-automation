import deep_heating/entity_id.{type ClimateEntityId}
import deep_heating/mode
import deep_heating/rooms/trv_actor
import deep_heating/temperature
import gleam/erlang/process.{type Name, type Subject}
import gleam/int
import gleam/option
import gleam/otp/actor
import gleeunit/should

// =============================================================================
// FFI for unique integer generation
// =============================================================================

@external(erlang, "erlang", "unique_integer")
fn unique_integer() -> Int

// =============================================================================
// Test Helpers
// =============================================================================

/// Create a mock RoomActor that uses actor.named() and forwards to a spy.
/// Returns the actor name and spy Subject for receiving messages.
fn make_mock_room_actor(
  test_id: String,
) -> #(Name(trv_actor.RoomMessage), Subject(trv_actor.RoomMessage)) {
  let spy = process.new_subject()
  let name =
    process.new_name(
      "mock_room_" <> test_id <> "_" <> int.to_string(unique_integer()),
    )

  // Start a mock actor that forwards messages to spy
  let assert Ok(_started) =
    actor.new(spy)
    |> actor.named(name)
    |> actor.on_message(fn(spy_subj, msg) {
      process.send(spy_subj, msg)
      actor.continue(spy_subj)
    })
    |> actor.start

  #(name, spy)
}

/// Test context for TRV actor tests
type TestContext {
  TestContext(
    room_actor_name: Name(trv_actor.RoomMessage),
    room_actor_spy: Subject(trv_actor.RoomMessage),
  )
}

fn make_test_context(test_id: String) -> TestContext {
  let #(room_actor_name, room_actor_spy) = make_mock_room_actor(test_id)
  TestContext(room_actor_name:, room_actor_spy:)
}

/// Helper to start a TRV actor with a unique name for testing
fn start_test_trv_actor(eid: ClimateEntityId, ctx: TestContext) {
  let name =
    process.new_name(
      "test_trv_"
      <> entity_id.climate_entity_id_to_string(eid)
      <> "_"
      <> int.to_string(unique_integer()),
    )
  trv_actor.start(eid, name, ctx.room_actor_name)
}

// =============================================================================
// Actor Startup Tests
// =============================================================================

pub fn trv_actor_starts_successfully_test() {
  // Create a valid climate entity ID
  let assert Ok(eid) = entity_id.climate_entity_id("climate.lounge_trv")

  // Create test context with mock named room actor
  let ctx = make_test_context("startup")

  // The TRV actor should start successfully
  let result = start_test_trv_actor(eid, ctx)
  should.be_ok(result)
}

pub fn trv_actor_is_alive_after_start_test() {
  let assert Ok(eid) = entity_id.climate_entity_id("climate.bedroom_trv")
  let ctx = make_test_context("alive")

  let assert Ok(started) = start_test_trv_actor(eid, ctx)

  // The actor should be running
  process.is_alive(started.pid) |> should.be_true
}

// =============================================================================
// GetState Tests
// =============================================================================

pub fn trv_actor_returns_initial_state_test() {
  let assert Ok(entity_id) = entity_id.climate_entity_id("climate.lounge_trv")
  let ctx = make_test_context("initial_state")

  let assert Ok(started) = start_test_trv_actor(entity_id, ctx)

  // Send GetState message and wait for response
  let reply_subject = process.new_subject()
  process.send(started.data, trv_actor.GetState(reply_subject))

  // Should receive the initial state
  let assert Ok(state) = process.receive(reply_subject, 1000)

  // Verify initial state values
  entity_id.climate_entity_id_to_string(state.entity_id)
  |> should.equal("climate.lounge_trv")
  state.temperature |> should.equal(option.None)
  state.target |> should.equal(option.None)
  state.mode |> should.equal(mode.HvacOff)
  state.is_heating |> should.be_false
}

// =============================================================================
// TrvUpdate Tests
// =============================================================================

pub fn trv_actor_updates_state_on_trv_update_test() {
  let assert Ok(entity_id) = entity_id.climate_entity_id("climate.lounge_trv")
  let ctx = make_test_context("updates_state")

  let assert Ok(started) = start_test_trv_actor(entity_id, ctx)

  // Create an update with new values
  let temp = temperature.temperature(21.5)
  let target = temperature.temperature(22.0)
  let update =
    trv_actor.TrvUpdate(
      temperature: option.Some(temp),
      target: option.Some(target),
      mode: mode.HvacHeat,
      is_heating: True,
    )

  // Send the update
  process.send(started.data, trv_actor.Update(update))

  // Give actor time to process
  process.sleep(10)

  // Query the state
  let reply_subject = process.new_subject()
  process.send(started.data, trv_actor.GetState(reply_subject))
  let assert Ok(state) = process.receive(reply_subject, 1000)

  // Verify state was updated
  state.temperature |> should.equal(option.Some(temp))
  state.target |> should.equal(option.Some(target))
  state.mode |> should.equal(mode.HvacHeat)
  state.is_heating |> should.be_true
}

// =============================================================================
// Room Actor Notification Tests
// =============================================================================

pub fn trv_actor_notifies_room_on_temperature_change_test() {
  let assert Ok(entity_id) = entity_id.climate_entity_id("climate.lounge_trv")
  let ctx = make_test_context("temp_change")

  let assert Ok(started) = start_test_trv_actor(entity_id, ctx)

  // Send an update with a new temperature
  let temp = temperature.temperature(21.5)
  let update =
    trv_actor.TrvUpdate(
      temperature: option.Some(temp),
      target: option.None,
      mode: mode.HvacOff,
      is_heating: False,
    )

  process.send(started.data, trv_actor.Update(update))

  // Room actor should receive a temperature changed notification
  let assert Ok(msg) = process.receive(ctx.room_actor_spy, 1000)
  case msg {
    trv_actor.TrvTemperatureChanged(eid, received_temp) -> {
      entity_id.climate_entity_id_to_string(eid)
      |> should.equal("climate.lounge_trv")
      received_temp |> should.equal(temp)
    }
    _ -> should.fail()
  }
}

pub fn trv_actor_notifies_room_on_target_change_test() {
  let assert Ok(entity_id) = entity_id.climate_entity_id("climate.lounge_trv")
  let ctx = make_test_context("target_change")

  let assert Ok(started) = start_test_trv_actor(entity_id, ctx)

  // Send an update with a new target
  let target = temperature.temperature(22.0)
  let update =
    trv_actor.TrvUpdate(
      temperature: option.None,
      target: option.Some(target),
      mode: mode.HvacOff,
      is_heating: False,
    )

  process.send(started.data, trv_actor.Update(update))

  // Room actor should receive a target changed notification
  let assert Ok(msg) = process.receive(ctx.room_actor_spy, 1000)
  case msg {
    trv_actor.TrvTargetChanged(eid, received_target) -> {
      entity_id.climate_entity_id_to_string(eid)
      |> should.equal("climate.lounge_trv")
      received_target |> should.equal(target)
    }
    _ -> should.fail()
  }
}

pub fn trv_actor_does_not_notify_when_temperature_unchanged_test() {
  let assert Ok(entity_id) = entity_id.climate_entity_id("climate.lounge_trv")
  let ctx = make_test_context("temp_unchanged")

  let assert Ok(started) = start_test_trv_actor(entity_id, ctx)

  // Set initial temperature
  let temp = temperature.temperature(21.5)
  let update =
    trv_actor.TrvUpdate(
      temperature: option.Some(temp),
      target: option.None,
      mode: mode.HvacOff,
      is_heating: False,
    )
  process.send(started.data, trv_actor.Update(update))

  // Drain the first notification
  let _ = process.receive(ctx.room_actor_spy, 100)

  // Send the same temperature again
  process.send(started.data, trv_actor.Update(update))

  // Should NOT receive another notification (timeout expected)
  case process.receive(ctx.room_actor_spy, 50) {
    Error(_) -> Nil
    // Expected - no message
    Ok(_) -> should.fail()
    // Unexpected message
  }
}

// =============================================================================
// Mode Change Notification Tests
// =============================================================================

pub fn trv_actor_notifies_room_on_mode_change_test() {
  let assert Ok(entity_id) = entity_id.climate_entity_id("climate.lounge_trv")
  let ctx = make_test_context("mode_change")

  let assert Ok(started) = start_test_trv_actor(entity_id, ctx)

  // Send an update with a new mode (initial mode is HvacOff)
  let update =
    trv_actor.TrvUpdate(
      temperature: option.None,
      target: option.None,
      mode: mode.HvacHeat,
      is_heating: False,
    )

  process.send(started.data, trv_actor.Update(update))

  // Room actor should receive a mode changed notification
  let assert Ok(msg) = process.receive(ctx.room_actor_spy, 1000)
  case msg {
    trv_actor.TrvModeChanged(eid, received_mode) -> {
      entity_id.climate_entity_id_to_string(eid)
      |> should.equal("climate.lounge_trv")
      received_mode |> should.equal(mode.HvacHeat)
    }
    _ -> should.fail()
  }
}

pub fn trv_actor_does_not_notify_when_mode_unchanged_test() {
  let assert Ok(entity_id) = entity_id.climate_entity_id("climate.lounge_trv")
  let ctx = make_test_context("mode_unchanged")

  let assert Ok(started) = start_test_trv_actor(entity_id, ctx)

  // Set initial mode to HvacHeat
  let update =
    trv_actor.TrvUpdate(
      temperature: option.None,
      target: option.None,
      mode: mode.HvacHeat,
      is_heating: False,
    )
  process.send(started.data, trv_actor.Update(update))

  // Drain the first notification
  let _ = process.receive(ctx.room_actor_spy, 100)

  // Send the same mode again
  process.send(started.data, trv_actor.Update(update))

  // Should NOT receive another notification (timeout expected)
  case process.receive(ctx.room_actor_spy, 50) {
    Error(_) -> Nil
    // Expected - no message
    Ok(_) -> should.fail()
    // Unexpected message
  }
}

// =============================================================================
// Is Heating Change Notification Tests
// =============================================================================

pub fn trv_actor_notifies_room_on_is_heating_change_test() {
  let assert Ok(entity_id) = entity_id.climate_entity_id("climate.lounge_trv")
  let ctx = make_test_context("is_heating_change")

  let assert Ok(started) = start_test_trv_actor(entity_id, ctx)

  // Send an update with is_heating = True (initial is False)
  let update =
    trv_actor.TrvUpdate(
      temperature: option.None,
      target: option.None,
      mode: mode.HvacOff,
      is_heating: True,
    )

  process.send(started.data, trv_actor.Update(update))

  // Room actor should receive an is_heating changed notification
  let assert Ok(msg) = process.receive(ctx.room_actor_spy, 1000)
  case msg {
    trv_actor.TrvIsHeatingChanged(eid, is_heating) -> {
      entity_id.climate_entity_id_to_string(eid)
      |> should.equal("climate.lounge_trv")
      is_heating |> should.be_true
    }
    _ -> should.fail()
  }
}

pub fn trv_actor_does_not_notify_when_is_heating_unchanged_test() {
  let assert Ok(entity_id) = entity_id.climate_entity_id("climate.lounge_trv")
  let ctx = make_test_context("is_heating_unchanged")

  let assert Ok(started) = start_test_trv_actor(entity_id, ctx)

  // Set initial is_heating to True
  let update =
    trv_actor.TrvUpdate(
      temperature: option.None,
      target: option.None,
      mode: mode.HvacOff,
      is_heating: True,
    )
  process.send(started.data, trv_actor.Update(update))

  // Drain the first notification
  let _ = process.receive(ctx.room_actor_spy, 100)

  // Send the same is_heating again
  process.send(started.data, trv_actor.Update(update))

  // Should NOT receive another notification (timeout expected)
  case process.receive(ctx.room_actor_spy, 50) {
    Error(_) -> Nil
    // Expected - no message
    Ok(_) -> should.fail()
    // Unexpected message
  }
}
