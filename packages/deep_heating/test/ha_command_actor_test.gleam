import deep_heating/entity_id
import deep_heating/home_assistant/client as home_assistant
import deep_heating/home_assistant/ha_command_actor.{type ApiCall}
import deep_heating/mode
import deep_heating/temperature
import deep_heating/timer
import gleam/erlang/process
import gleam/list
import gleeunit/should

// =============================================================================
// Test Helpers
// =============================================================================

/// Start a test HaCommandActor with sensible defaults.
/// Uses instant_send_after for fast tests - debounce timers fire immediately.
/// Returns tuple of (actor subject, api_spy subject) for assertions.
fn make_test_context() -> #(
  process.Subject(ha_command_actor.Message),
  process.Subject(ApiCall),
) {
  let api_spy: process.Subject(ApiCall) = process.new_subject()
  let assert Ok(started) =
    ha_command_actor.start_with_options(
      ha_client: home_assistant.HaClient("http://localhost:8123", "test-token"),
      api_spy: api_spy,
      debounce_ms: 50,
      skip_http: True,
      send_after: timer.instant_send_after,
    )
  #(started.data, api_spy)
}

/// Start a test HaCommandActor that uses real timers for debounce.
/// Use this for tests that specifically test debounce coalescence behavior.
/// These tests need real timing to allow multiple commands to coalesce.
fn make_debounce_test_context() -> #(
  process.Subject(ha_command_actor.Message),
  process.Subject(ApiCall),
) {
  let api_spy: process.Subject(ApiCall) = process.new_subject()
  let assert Ok(started) =
    ha_command_actor.start_with_options(
      ha_client: home_assistant.HaClient("http://localhost:8123", "test-token"),
      api_spy: api_spy,
      debounce_ms: 50,
      skip_http: True,
      send_after: timer.real_send_after,
    )
  #(started.data, api_spy)
}

// =============================================================================
// Actor Startup Tests
// =============================================================================

pub fn ha_command_actor_starts_successfully_test() {
  // make_test_context() asserts Ok, so just calling it verifies startup
  let _ = make_test_context()
}

// =============================================================================
// Command Handling Tests
// =============================================================================

pub fn sends_api_call_after_debounce_test() {
  // When a TRV action is received, the actor should call the HA API
  // after the debounce period
  let #(actor, api_spy) = make_test_context()
  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  // Send a TRV action
  process.send(
    actor,
    ha_command_actor.SetTrvAction(
      entity_id: trv_id,
      mode: mode.HvacHeat,
      target: temperature.temperature(21.0),
    ),
  )

  // Wait for debounce + processing time
  process.sleep(100)

  // Should receive API call notification
  let assert Ok(call) = process.receive(api_spy, 100)

  case call {
    ha_command_actor.TrvApiCall(entity_id, called_mode, called_target) -> {
      entity_id |> should.equal(trv_id)
      called_mode |> should.equal(mode.HvacHeat)
      temperature.unwrap(called_target) |> should.equal(21.0)
    }
    _ -> should.fail()
  }
}

// =============================================================================
// Debounce Tests
// =============================================================================

pub fn debounces_rapid_commands_to_same_trv_test() {
  // When multiple commands are sent rapidly to the same TRV,
  // only the LAST one should be executed after the debounce period
  // Uses real timers since we're testing debounce coalescence behavior
  let #(actor, api_spy) = make_debounce_test_context()
  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  // Send multiple rapid commands to the same TRV
  process.send(
    actor,
    ha_command_actor.SetTrvAction(
      entity_id: trv_id,
      mode: mode.HvacHeat,
      target: temperature.temperature(18.0),
    ),
  )
  process.sleep(10)
  process.send(
    actor,
    ha_command_actor.SetTrvAction(
      entity_id: trv_id,
      mode: mode.HvacHeat,
      target: temperature.temperature(19.0),
    ),
  )
  process.sleep(10)
  process.send(
    actor,
    ha_command_actor.SetTrvAction(
      entity_id: trv_id,
      mode: mode.HvacHeat,
      target: temperature.temperature(21.0),
    ),
  )

  // Wait for debounce + processing time
  process.sleep(100)

  // Should receive ONLY ONE API call with the LAST value
  let assert Ok(call) = process.receive(api_spy, 100)

  case call {
    ha_command_actor.TrvApiCall(entity_id, called_mode, called_target) -> {
      entity_id |> should.equal(trv_id)
      called_mode |> should.equal(mode.HvacHeat)
      // Should be the LAST value sent (21.0)
      temperature.unwrap(called_target) |> should.equal(21.0)
    }
    _ -> should.fail()
  }

  // Should NOT receive any more API calls
  process.sleep(50)
  let result = process.receive(api_spy, 50)
  result |> should.be_error
}

pub fn debounces_trvs_independently_test() {
  // Commands to different TRVs should be debounced independently
  // (each TRV has its own debounce timer)
  let #(actor, api_spy) = make_test_context()
  let assert Ok(trv1) = entity_id.climate_entity_id("climate.lounge_trv")
  let assert Ok(trv2) = entity_id.climate_entity_id("climate.bedroom_trv")

  // Send commands to two different TRVs
  process.send(
    actor,
    ha_command_actor.SetTrvAction(
      entity_id: trv1,
      mode: mode.HvacHeat,
      target: temperature.temperature(20.0),
    ),
  )
  process.send(
    actor,
    ha_command_actor.SetTrvAction(
      entity_id: trv2,
      mode: mode.HvacAuto,
      target: temperature.temperature(22.0),
    ),
  )

  // Wait for debounce + processing time
  process.sleep(100)

  // Should receive TWO API calls (one for each TRV)
  let assert Ok(call1) = process.receive(api_spy, 100)
  let assert Ok(call2) = process.receive(api_spy, 100)

  // Collect the entity IDs and targets that were called
  let calls = [call1, call2]

  // Verify we got both TRVs (order may vary)
  let has_trv1 =
    list.any(calls, fn(c) {
      case c {
        ha_command_actor.TrvApiCall(eid, _, _) -> eid == trv1
        _ -> False
      }
    })
  let has_trv2 =
    list.any(calls, fn(c) {
      case c {
        ha_command_actor.TrvApiCall(eid, _, _) -> eid == trv2
        _ -> False
      }
    })

  has_trv1 |> should.be_true
  has_trv2 |> should.be_true
}

// =============================================================================
// Heating Action Tests
// =============================================================================

pub fn sends_heating_api_call_after_debounce_test() {
  // When a heating action is received, it should call the HA API
  // after the debounce period
  let #(actor, api_spy) = make_test_context()
  let assert Ok(heating_id) =
    entity_id.climate_entity_id("climate.main_heating")

  // Send a heating action
  process.send(
    actor,
    ha_command_actor.SetHeatingAction(
      entity_id: heating_id,
      mode: mode.HvacHeat,
      target: temperature.temperature(22.0),
    ),
  )

  // Wait for debounce + processing time
  process.sleep(100)

  // Should receive API call notification
  let assert Ok(call) = process.receive(api_spy, 100)

  case call {
    ha_command_actor.HeatingApiCall(entity_id, called_mode, called_target) -> {
      entity_id |> should.equal(heating_id)
      called_mode |> should.equal(mode.HvacHeat)
      temperature.unwrap(called_target) |> should.equal(22.0)
    }
    _ -> should.fail()
  }
}

pub fn debounces_rapid_heating_commands_test() {
  // Multiple rapid heating commands should be debounced to one call
  // Uses real timers since we're testing debounce coalescence behavior
  let #(actor, api_spy) = make_debounce_test_context()
  let assert Ok(heating_id) =
    entity_id.climate_entity_id("climate.main_heating")

  // Send multiple rapid heating commands
  process.send(
    actor,
    ha_command_actor.SetHeatingAction(
      entity_id: heating_id,
      mode: mode.HvacHeat,
      target: temperature.temperature(18.0),
    ),
  )
  process.sleep(10)
  process.send(
    actor,
    ha_command_actor.SetHeatingAction(
      entity_id: heating_id,
      mode: mode.HvacHeat,
      target: temperature.temperature(20.0),
    ),
  )
  process.sleep(10)
  process.send(
    actor,
    ha_command_actor.SetHeatingAction(
      entity_id: heating_id,
      mode: mode.HvacAuto,
      target: temperature.temperature(22.0),
    ),
  )

  // Wait for debounce + processing time
  process.sleep(100)

  // Should receive ONLY ONE API call with the LAST values
  let assert Ok(call) = process.receive(api_spy, 100)

  case call {
    ha_command_actor.HeatingApiCall(entity_id, called_mode, called_target) -> {
      entity_id |> should.equal(heating_id)
      called_mode |> should.equal(mode.HvacAuto)
      temperature.unwrap(called_target) |> should.equal(22.0)
    }
    _ -> should.fail()
  }

  // Should NOT receive any more API calls
  process.sleep(50)
  let result = process.receive(api_spy, 50)
  result |> should.be_error
}

// =============================================================================
// Child Spec / Supervision Tests
// =============================================================================

pub fn child_spec_creates_valid_specification_test() {
  // child_spec should return a valid ChildSpecification for OTP supervision
  let name = process.new_name("test_ha_command_actor")
  let ha_client = home_assistant.HaClient("http://localhost:8123", "test-token")
  let debounce_ms = 50

  // This should compile and return a ChildSpecification
  let _child_spec = ha_command_actor.child_spec(name, ha_client, debounce_ms)

  // If we got here without error, the child_spec function exists and compiles
  should.be_true(True)
}

// =============================================================================
// Injectable Timer Tests
// =============================================================================

pub fn instant_send_after_delivers_immediately_test() {
  // When using instant_send_after, debounce timer fires immediately
  // so we don't need process.sleep() to wait for the API call
  let api_spy: process.Subject(ApiCall) = process.new_subject()
  let assert Ok(started) =
    ha_command_actor.start_with_options(
      ha_client: home_assistant.HaClient("http://localhost:8123", "test-token"),
      api_spy: api_spy,
      debounce_ms: 5000,
      skip_http: True,
      send_after: timer.instant_send_after,
    )
  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.test_trv")

  // Send a TRV action - with instant_send_after, the debounce timer
  // fires immediately (no 5 second wait)
  process.send(
    started.data,
    ha_command_actor.SetTrvAction(
      entity_id: trv_id,
      mode: mode.HvacHeat,
      target: temperature.temperature(21.0),
    ),
  )

  // Should receive API call immediately (no sleep needed!)
  // Using a short timeout since delivery should be instant
  let assert Ok(call) = process.receive(api_spy, 100)

  case call {
    ha_command_actor.TrvApiCall(entity_id, called_mode, called_target) -> {
      entity_id |> should.equal(trv_id)
      called_mode |> should.equal(mode.HvacHeat)
      temperature.unwrap(called_target) |> should.equal(21.0)
    }
    _ -> should.fail()
  }
}

// =============================================================================
// Graceful Shutdown Tests
// =============================================================================

pub fn shutdown_cancels_pending_trv_timers_test() {
  // When Shutdown is called, pending debounce timers should be cancelled
  // and no API calls should be made
  let api_spy: process.Subject(ApiCall) = process.new_subject()
  let assert Ok(started) =
    ha_command_actor.start_with_options(
      ha_client: home_assistant.HaClient("http://localhost:8123", "test-token"),
      api_spy: api_spy,
      debounce_ms: 200,
      skip_http: True,
      send_after: timer.real_send_after,
    )
  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.test_trv")

  // Send a TRV action to start the debounce timer
  process.send(
    started.data,
    ha_command_actor.SetTrvAction(
      entity_id: trv_id,
      mode: mode.HvacHeat,
      target: temperature.temperature(21.0),
    ),
  )

  // Immediately send Shutdown (before the 200ms debounce fires)
  process.send(started.data, ha_command_actor.Shutdown)

  // Wait longer than the debounce period would have been
  process.sleep(300)

  // Should NOT receive any API calls (timer was cancelled)
  let result = process.receive(api_spy, 100)
  result |> should.be_error
}

pub fn shutdown_cancels_pending_heating_timer_test() {
  // When Shutdown is called, pending heating timer should be cancelled
  let api_spy: process.Subject(ApiCall) = process.new_subject()
  let assert Ok(started) =
    ha_command_actor.start_with_options(
      ha_client: home_assistant.HaClient("http://localhost:8123", "test-token"),
      api_spy: api_spy,
      debounce_ms: 200,
      skip_http: True,
      send_after: timer.real_send_after,
    )
  let assert Ok(heating_id) =
    entity_id.climate_entity_id("climate.main_heating")

  // Send a heating action to start the debounce timer
  process.send(
    started.data,
    ha_command_actor.SetHeatingAction(
      entity_id: heating_id,
      mode: mode.HvacHeat,
      target: temperature.temperature(22.0),
    ),
  )

  // Immediately send Shutdown (before the 200ms debounce fires)
  process.send(started.data, ha_command_actor.Shutdown)

  // Wait longer than the debounce period would have been
  process.sleep(300)

  // Should NOT receive any API calls (timer was cancelled)
  let result = process.receive(api_spy, 100)
  result |> should.be_error
}

pub fn shutdown_cancels_multiple_pending_timers_test() {
  // When Shutdown is called, all pending timers should be cancelled
  let api_spy: process.Subject(ApiCall) = process.new_subject()
  let assert Ok(started) =
    ha_command_actor.start_with_options(
      ha_client: home_assistant.HaClient("http://localhost:8123", "test-token"),
      api_spy: api_spy,
      debounce_ms: 200,
      skip_http: True,
      send_after: timer.real_send_after,
    )
  let assert Ok(trv1) = entity_id.climate_entity_id("climate.trv1")
  let assert Ok(trv2) = entity_id.climate_entity_id("climate.trv2")
  let assert Ok(heating_id) =
    entity_id.climate_entity_id("climate.main_heating")

  // Start multiple timers
  process.send(
    started.data,
    ha_command_actor.SetTrvAction(
      entity_id: trv1,
      mode: mode.HvacHeat,
      target: temperature.temperature(20.0),
    ),
  )
  process.send(
    started.data,
    ha_command_actor.SetTrvAction(
      entity_id: trv2,
      mode: mode.HvacHeat,
      target: temperature.temperature(21.0),
    ),
  )
  process.send(
    started.data,
    ha_command_actor.SetHeatingAction(
      entity_id: heating_id,
      mode: mode.HvacHeat,
      target: temperature.temperature(22.0),
    ),
  )

  // Immediately send Shutdown
  process.send(started.data, ha_command_actor.Shutdown)

  // Wait longer than the debounce period
  process.sleep(300)

  // Should NOT receive any API calls (all timers were cancelled)
  let result = process.receive(api_spy, 100)
  result |> should.be_error
}
