import deep_heating/actor/ha_command_actor.{type ApiCall}
import deep_heating/entity_id
import deep_heating/home_assistant
import deep_heating/mode
import deep_heating/temperature
import gleam/erlang/process
import gleam/list
import gleeunit/should

// =============================================================================
// Actor Startup Tests
// =============================================================================

pub fn ha_command_actor_starts_successfully_test() {
  // Create a spy subject to capture API calls
  let api_spy: process.Subject(ApiCall) = process.new_subject()

  // HaCommandActor should start successfully
  let result =
    ha_command_actor.start_with_options(
      ha_client: home_assistant.HaClient("http://localhost:8123", "test-token"),
      api_spy: api_spy,
      debounce_ms: 50,
      skip_http: True,
    )
  should.be_ok(result)
}

// =============================================================================
// Command Handling Tests
// =============================================================================

pub fn sends_api_call_after_debounce_test() {
  // When a TRV action is received, the actor should call the HA API
  // after the debounce period
  let api_spy: process.Subject(ApiCall) = process.new_subject()

  let assert Ok(started) =
    ha_command_actor.start_with_options(
      ha_client: home_assistant.HaClient("http://localhost:8123", "test-token"),
      api_spy: api_spy,
      debounce_ms: 50,
      skip_http: True,
    )

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  // Send a TRV action
  process.send(
    started.data,
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
  let api_spy: process.Subject(ha_command_actor.ApiCall) = process.new_subject()

  let assert Ok(started) =
    ha_command_actor.start_with_options(
      ha_client: home_assistant.HaClient("http://localhost:8123", "test-token"),
      api_spy: api_spy,
      debounce_ms: 50,
      skip_http: True,
    )

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  // Send multiple rapid commands to the same TRV
  process.send(
    started.data,
    ha_command_actor.SetTrvAction(
      entity_id: trv_id,
      mode: mode.HvacHeat,
      target: temperature.temperature(18.0),
    ),
  )
  process.sleep(10)
  process.send(
    started.data,
    ha_command_actor.SetTrvAction(
      entity_id: trv_id,
      mode: mode.HvacHeat,
      target: temperature.temperature(19.0),
    ),
  )
  process.sleep(10)
  process.send(
    started.data,
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
  let api_spy: process.Subject(ha_command_actor.ApiCall) = process.new_subject()

  let assert Ok(started) =
    ha_command_actor.start_with_options(
      ha_client: home_assistant.HaClient("http://localhost:8123", "test-token"),
      api_spy: api_spy,
      debounce_ms: 50,
      skip_http: True,
    )

  let assert Ok(trv1) = entity_id.climate_entity_id("climate.lounge_trv")
  let assert Ok(trv2) = entity_id.climate_entity_id("climate.bedroom_trv")

  // Send commands to two different TRVs
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
  let api_spy: process.Subject(ha_command_actor.ApiCall) = process.new_subject()

  let assert Ok(started) =
    ha_command_actor.start_with_options(
      ha_client: home_assistant.HaClient("http://localhost:8123", "test-token"),
      api_spy: api_spy,
      debounce_ms: 50,
      skip_http: True,
    )

  let assert Ok(heating_id) =
    entity_id.climate_entity_id("climate.main_heating")

  // Send a heating action
  process.send(
    started.data,
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
  let api_spy: process.Subject(ha_command_actor.ApiCall) = process.new_subject()

  let assert Ok(started) =
    ha_command_actor.start_with_options(
      ha_client: home_assistant.HaClient("http://localhost:8123", "test-token"),
      api_spy: api_spy,
      debounce_ms: 50,
      skip_http: True,
    )

  let assert Ok(heating_id) =
    entity_id.climate_entity_id("climate.main_heating")

  // Send multiple rapid heating commands
  process.send(
    started.data,
    ha_command_actor.SetHeatingAction(
      entity_id: heating_id,
      mode: mode.HvacHeat,
      target: temperature.temperature(18.0),
    ),
  )
  process.sleep(10)
  process.send(
    started.data,
    ha_command_actor.SetHeatingAction(
      entity_id: heating_id,
      mode: mode.HvacHeat,
      target: temperature.temperature(20.0),
    ),
  )
  process.sleep(10)
  process.send(
    started.data,
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
