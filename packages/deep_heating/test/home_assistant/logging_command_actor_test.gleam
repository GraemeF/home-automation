//// Tests for LoggingCommandActor - dry-run mode that logs commands instead of sending to HA

import deep_heating/entity_id
import deep_heating/home_assistant/ha_command_actor.{
  HeatingApiCall, SetHeatingAction, SetTrvAction, TrvApiCall,
}
import deep_heating/home_assistant/logging_command_actor
import deep_heating/mode
import deep_heating/temperature
import gleam/erlang/process
import gleam/int
import gleeunit/should

// =============================================================================
// Tests
// =============================================================================

pub fn logging_actor_logs_trv_action_immediately_test() {
  let spy: process.Subject(ha_command_actor.ApiCall) = process.new_subject()

  // Start the logging command actor
  let assert Ok(started) = logging_command_actor.start(api_spy: spy)

  // Create and send a TRV action
  let assert Ok(entity_id) = entity_id.climate_entity_id("climate.living_room")
  process.send(
    started.data,
    SetTrvAction(
      entity_id: entity_id,
      mode: mode.HvacHeat,
      target: temperature.temperature(21.0),
    ),
  )

  // Should receive immediately (no debounce)
  let assert Ok(received) = process.receive(spy, 100)

  case received {
    TrvApiCall(eid, hvac_mode, target) -> {
      entity_id.climate_entity_id_to_string(eid)
      |> should.equal("climate.living_room")
      hvac_mode |> should.equal(mode.HvacHeat)
      temperature.unwrap(target) |> should.equal(21.0)
    }
    _ -> should.fail()
  }
}

pub fn logging_actor_logs_heating_action_immediately_test() {
  let spy: process.Subject(ha_command_actor.ApiCall) = process.new_subject()

  // Start the logging command actor
  let assert Ok(started) = logging_command_actor.start(api_spy: spy)

  // Create and send a heating action
  let assert Ok(entity_id) = entity_id.climate_entity_id("climate.main_heating")
  process.send(
    started.data,
    SetHeatingAction(
      entity_id: entity_id,
      mode: mode.HvacHeat,
      target: temperature.temperature(25.0),
    ),
  )

  // Should receive immediately (no debounce)
  let assert Ok(received) = process.receive(spy, 100)

  case received {
    HeatingApiCall(eid, hvac_mode, target) -> {
      entity_id.climate_entity_id_to_string(eid)
      |> should.equal("climate.main_heating")
      hvac_mode |> should.equal(mode.HvacHeat)
      temperature.unwrap(target) |> should.equal(25.0)
    }
    _ -> should.fail()
  }
}

pub fn logging_actor_starts_with_name_test() {
  let spy: process.Subject(ha_command_actor.ApiCall) = process.new_subject()
  let name = process.new_name("test_logging_cmd_" <> unique_id())

  // Start the named logging command actor
  let assert Ok(started) =
    logging_command_actor.start_named(name: name, api_spy: spy)

  // Should be able to look it up by name
  let named_subject: process.Subject(ha_command_actor.Message) =
    process.named_subject(name)

  // Send via named subject
  let assert Ok(entity_id) = entity_id.climate_entity_id("climate.test_trv")
  process.send(
    named_subject,
    SetTrvAction(
      entity_id: entity_id,
      mode: mode.HvacHeat,
      target: temperature.temperature(19.0),
    ),
  )

  // Should receive the spy notification
  let assert Ok(TrvApiCall(_, _, _)) = process.receive(spy, 100)

  // Cleanup
  process.send(started.data, ha_command_actor.Shutdown)
}

fn unique_id() -> String {
  int.to_string(erlang_unique_integer())
}

@external(erlang, "erlang", "unique_integer")
fn erlang_unique_integer() -> Int

pub fn logging_actor_handles_shutdown_test() {
  let spy: process.Subject(ha_command_actor.ApiCall) = process.new_subject()

  // Start the logging command actor
  let assert Ok(started) = logging_command_actor.start(api_spy: spy)

  // Send shutdown
  process.send(started.data, ha_command_actor.Shutdown)

  // Give it a moment to process
  process.sleep(50)

  // Actor should be dead - sending should not crash us but actor won't respond
  // We verify by checking the process is no longer alive
  let is_alive = case process.subject_owner(started.data) {
    Ok(pid) -> process.is_alive(pid)
    Error(_) -> False
  }

  is_alive |> should.equal(False)
}
