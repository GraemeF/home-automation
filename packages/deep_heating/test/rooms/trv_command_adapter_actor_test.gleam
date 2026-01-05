//// Tests for TrvCommandAdapterActor with simple named pattern.
////
//// The adapter should:
//// - Be addressable via named_subject() after registration
//// - Forward TrvCommand messages to HaCommandActor (looked up by name)
//// - Survive OTP supervision restarts (names persist, Subjects don't)

import deep_heating/entity_id
import deep_heating/home_assistant/ha_command_actor
import deep_heating/mode
import deep_heating/rooms/room_decision_actor.{type TrvCommand, TrvCommand}
import deep_heating/rooms/trv_command_adapter_actor
import deep_heating/temperature
import gleam/erlang/process
import gleam/otp/actor
import gleeunit/should

// =============================================================================
// Test helper: Mock HA Command Actor that uses actor.named() properly
// =============================================================================

/// State for mock HA command actor - forwards to spy
type MockHaState {
  MockHaState(spy: process.Subject(ha_command_actor.Message))
}

/// Start a mock HA command actor with proper naming support.
/// Uses actor.named() so it can be found via named_subject().
/// Receives ha_command_actor.Message directly to match the adapter's expectations.
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
    // Forward to spy for test verification
    process.send(state.spy, msg)
    actor.continue(state)
  })
  |> actor.start
}

// =============================================================================
// Tests
// =============================================================================

/// Test that the adapter forwards TrvCommand to HaCommandActor via name lookup.
///
/// This test verifies the core functionality:
/// 1. Adapter can be started with start_named
/// 2. TrvCommand messages get converted and forwarded to HaCommandActor
pub fn adapter_forwards_trv_command_to_ha_command_actor_test() {
  // Create unique names for this test
  let ha_command_name: process.Name(ha_command_actor.Message) =
    process.new_name("test_ha_command_trv_fwd")
  let adapter_name = process.new_name("test_trv_adapter_fwd")

  // Create a spy to observe what the adapter sends
  let spy: process.Subject(ha_command_actor.Message) = process.new_subject()

  // Start a mock HA command actor with proper naming
  let assert Ok(_mock_started) =
    start_mock_ha_command_actor(ha_command_name, spy)

  // Start the adapter pointing at the HA command actor's name
  let assert Ok(adapter_started) =
    trv_command_adapter_actor.start_named(
      name: adapter_name,
      ha_command_name: ha_command_name,
    )

  // Send a TrvCommand via the returned Subject
  let assert Ok(eid) = entity_id.climate_entity_id("climate.test_trv")
  let target = temperature.temperature(21.0)
  process.send(adapter_started.data, TrvCommand(eid, mode.HvacHeat, target))

  // Wait for processing
  process.sleep(50)

  // Verify the mock HA command actor received the converted message
  let assert Ok(received) = process.receive(spy, 1000)
  case received {
    ha_command_actor.SetTrvAction(recv_entity, recv_mode, recv_target) -> {
      recv_entity |> should.equal(eid)
      recv_mode |> should.equal(mode.HvacHeat)
      recv_target |> should.equal(target)
    }
    _ -> panic as "Expected SetTrvAction"
  }
}

/// Test that the adapter can be looked up by name after starting
pub fn adapter_can_be_found_via_named_subject_test() {
  // Create unique names for this test
  let ha_command_name: process.Name(ha_command_actor.Message) =
    process.new_name("test_ha_command_lookup")
  let adapter_name = process.new_name("test_trv_adapter_lookup")

  // Create spy and start mock HA command actor
  let spy: process.Subject(ha_command_actor.Message) = process.new_subject()
  let assert Ok(_mock_started) =
    start_mock_ha_command_actor(ha_command_name, spy)

  // Start the adapter
  let assert Ok(_adapter_started) =
    trv_command_adapter_actor.start_named(
      name: adapter_name,
      ha_command_name: ha_command_name,
    )

  // Look up the adapter by name and send a message
  let looked_up: process.Subject(TrvCommand) =
    process.named_subject(adapter_name)

  let assert Ok(eid) = entity_id.climate_entity_id("climate.lookup_test")
  let target = temperature.temperature(19.5)
  process.send(looked_up, TrvCommand(eid, mode.HvacOff, target))

  // Wait for processing
  process.sleep(50)

  // Verify the command was received via the looked-up Subject
  let assert Ok(received) = process.receive(spy, 1000)
  case received {
    ha_command_actor.SetTrvAction(recv_entity, recv_mode, recv_target) -> {
      recv_entity |> should.equal(eid)
      recv_mode |> should.equal(mode.HvacOff)
      recv_target |> should.equal(target)
    }
    _ -> panic as "Expected SetTrvAction"
  }
}
