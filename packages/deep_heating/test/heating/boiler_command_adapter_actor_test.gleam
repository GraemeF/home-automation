//// Tests for BoilerCommandAdapterActor - verifies named actor pattern works

import deep_heating/entity_id
import deep_heating/heating/boiler_command_adapter_actor
import deep_heating/heating/heating_control_actor.{BoilerCommand}
import deep_heating/home_assistant/ha_command_actor
import deep_heating/mode
import deep_heating/temperature
import gleam/erlang/process
import gleam/int
import gleam/otp/actor
import gleeunit/should

// =============================================================================
// Test Helpers
// =============================================================================

/// Counter for unique test names
@external(erlang, "erlang", "unique_integer")
fn unique_integer() -> Int

/// State for mock HA command actor
type MockHaState {
  MockHaState(spy: process.Subject(ha_command_actor.Message))
}

/// Start a mock HA command actor with proper naming support.
fn start_mock_ha_command_actor(
  name: process.Name(ha_command_actor.Message),
  spy: process.Subject(ha_command_actor.Message),
) -> Result(
  actor.Started(process.Subject(ha_command_actor.Message)),
  actor.StartError,
) {
  actor.new(MockHaState(spy: spy))
  |> actor.named(name)
  |> actor.on_message(fn(state: MockHaState, msg: ha_command_actor.Message) {
    process.send(state.spy, msg)
    actor.continue(state)
  })
  |> actor.start
}

// =============================================================================
// Tests
// =============================================================================

pub fn boiler_adapter_starts_successfully_test() {
  let unique = int.to_string(unique_integer())
  let ha_command_name = process.new_name("test_ha_cmd_" <> unique)
  let adapter_name = process.new_name("test_boiler_adapter_" <> unique)
  let spy: process.Subject(ha_command_actor.Message) = process.new_subject()

  // Start the mock HA command actor
  let assert Ok(_) = start_mock_ha_command_actor(ha_command_name, spy)

  // Start the boiler adapter
  let result =
    boiler_command_adapter_actor.start_named(
      name: adapter_name,
      ha_command_name: ha_command_name,
    )

  should.be_ok(result)
}

pub fn boiler_adapter_forwards_commands_to_ha_test() {
  let unique = int.to_string(unique_integer())
  let ha_command_name = process.new_name("test_ha_cmd_" <> unique)
  let adapter_name = process.new_name("test_boiler_adapter_" <> unique)
  let spy: process.Subject(ha_command_actor.Message) = process.new_subject()

  // Start the mock HA command actor
  let assert Ok(_) = start_mock_ha_command_actor(ha_command_name, spy)

  // Start the boiler adapter
  let assert Ok(adapter_started) =
    boiler_command_adapter_actor.start_named(
      name: adapter_name,
      ha_command_name: ha_command_name,
    )

  // Create a BoilerCommand
  let assert Ok(entity_id) = entity_id.climate_entity_id("climate.main_heating")
  let command =
    BoilerCommand(
      entity_id: entity_id,
      mode: mode.HvacHeat,
      target: temperature.temperature(20.0),
    )

  // Send command to adapter
  process.send(adapter_started.data, command)

  // Verify the mock HA command actor received the correct message
  let assert Ok(received) = process.receive(spy, 1000)

  case received {
    ha_command_actor.SetHeatingAction(eid, hvac_mode, _target) -> {
      entity_id.climate_entity_id_to_string(eid)
      |> should.equal("climate.main_heating")
      hvac_mode |> should.equal(mode.HvacHeat)
    }
    _ -> should.fail()
  }
}
