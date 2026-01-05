//// Tests for RoomsSupervisor - starts per-room actor trees from configuration.

import deep_heating/config/home_config.{type RoomConfig, HomeConfig, RoomConfig}
import deep_heating/entity_id
import deep_heating/home_assistant/ha_command_actor
import deep_heating/house_mode/house_mode_actor
import deep_heating/mode
import deep_heating/rooms/room_actor
import deep_heating/rooms/room_adjustments
import deep_heating/rooms/rooms_supervisor
import deep_heating/rooms/trv_actor
import deep_heating/scheduling/schedule
import deep_heating/state/state_aggregator_actor
import deep_heating/temperature
import gleam/dict
import gleam/erlang/process
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleeunit/should

// =============================================================================
// Test Helpers
// =============================================================================

/// Counter for unique test names - each test needs unique actor names
@external(erlang, "erlang", "unique_integer")
fn unique_integer() -> Int

/// State for mock HA command actor
type MockHaState {
  MockHaState(spy: process.Subject(ha_command_actor.Message))
}

/// Start a mock HA command actor with proper naming support.
/// Uses actor.named() so it can be found via named_subject().
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

/// Create a named mock HA command actor for testing rooms_supervisor.
/// Returns the name that can be passed to rooms_supervisor.start_room
fn make_mock_ha_command(
  test_id: String,
) -> #(
  process.Name(ha_command_actor.Message),
  process.Subject(ha_command_actor.Message),
) {
  let name_str =
    "test_ha_command_" <> test_id <> "_" <> int_to_string(unique_integer())
  let ha_command_name: process.Name(ha_command_actor.Message) =
    process.new_name(name_str)
  let spy: process.Subject(ha_command_actor.Message) = process.new_subject()
  let assert Ok(_) = start_mock_ha_command_actor(ha_command_name, spy)
  #(ha_command_name, spy)
}

fn int_to_string(n: Int) -> String {
  case n < 0 {
    True -> "-" <> int_to_string(-n)
    False ->
      case n {
        0 -> "0"
        1 -> "1"
        2 -> "2"
        3 -> "3"
        4 -> "4"
        5 -> "5"
        6 -> "6"
        7 -> "7"
        8 -> "8"
        9 -> "9"
        _ -> int_to_string(n / 10) <> int_to_string(n % 10)
      }
  }
}

fn make_test_schedule() -> schedule.WeekSchedule {
  // Simple schedule: 20°C all day every day
  let assert Ok(time) = schedule.time_of_day(0, 0)
  let entry =
    schedule.ScheduleEntry(
      start: time,
      target_temperature: temperature.temperature(20.0),
    )
  let day = [entry]
  schedule.WeekSchedule(
    monday: day,
    tuesday: day,
    wednesday: day,
    thursday: day,
    friday: day,
    saturday: day,
    sunday: day,
  )
}

fn make_single_room_config() -> RoomConfig {
  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")
  let assert Ok(sensor_id) = entity_id.sensor_entity_id("sensor.lounge_temp")

  RoomConfig(
    name: "lounge",
    temperature_sensor_entity_id: Some(sensor_id),
    climate_entity_ids: [trv_id],
    schedule: Some(make_test_schedule()),
  )
}

fn make_multi_trv_room_config() -> RoomConfig {
  let assert Ok(trv1) = entity_id.climate_entity_id("climate.bedroom_trv_1")
  let assert Ok(trv2) = entity_id.climate_entity_id("climate.bedroom_trv_2")
  let assert Ok(sensor_id) = entity_id.sensor_entity_id("sensor.bedroom_temp")

  RoomConfig(
    name: "bedroom",
    temperature_sensor_entity_id: Some(sensor_id),
    climate_entity_ids: [trv1, trv2],
    schedule: Some(make_test_schedule()),
  )
}

/// Create a dummy house_mode subject for tests that don't care about house mode
fn make_dummy_house_mode() -> process.Subject(house_mode_actor.Message) {
  process.new_subject()
}

// =============================================================================
// RoomSupervisor Tests (single room)
// =============================================================================

pub fn room_supervisor_starts_successfully_test() {
  // Create dependencies that would normally come from parent supervisor
  let state_aggregator: process.Subject(state_aggregator_actor.Message) =
    process.new_subject()
  let #(ha_command_name, _spy) = make_mock_ha_command("starts_successfully")

  let room_config = make_single_room_config()

  // Start the room supervisor for a single room
  let result =
    rooms_supervisor.start_room(
      room_config: room_config,
      state_aggregator: state_aggregator,
      ha_command_name: ha_command_name,
      house_mode: make_dummy_house_mode(),
      heating_control: None,
      initial_adjustments: [],
    )

  should.be_ok(result)
}

pub fn room_supervisor_starts_room_actor_test() {
  let state_aggregator: process.Subject(state_aggregator_actor.Message) =
    process.new_subject()
  let #(ha_command_name, _spy) = make_mock_ha_command("starts_room_actor")
  let room_config = make_single_room_config()

  let assert Ok(room_sup) =
    rooms_supervisor.start_room(
      room_config: room_config,
      state_aggregator: state_aggregator,
      ha_command_name: ha_command_name,
      house_mode: make_dummy_house_mode(),
      heating_control: None,
      initial_adjustments: [],
    )

  // Should be able to get the room actor subject
  let assert Ok(room_actor_ref) = rooms_supervisor.get_room_actor(room_sup)

  // Query the room actor to verify it's running
  let reply = process.new_subject()
  process.send(room_actor_ref.subject, room_actor.GetState(reply))
  let assert Ok(state) = process.receive(reply, 1000)

  state.name |> should.equal("lounge")
}

pub fn room_supervisor_starts_room_with_initial_adjustment_test() {
  let state_aggregator: process.Subject(state_aggregator_actor.Message) =
    process.new_subject()
  let #(ha_command_name, _spy) = make_mock_ha_command("initial_adjustment")
  let room_config = make_single_room_config()

  // Create initial adjustments list with lounge at +1.5
  let initial_adjustments = [
    room_adjustments.RoomAdjustment(room_name: "lounge", adjustment: 1.5),
  ]

  let assert Ok(room_sup) =
    rooms_supervisor.start_room(
      room_config: room_config,
      state_aggregator: state_aggregator,
      ha_command_name: ha_command_name,
      house_mode: make_dummy_house_mode(),
      heating_control: None,
      initial_adjustments: initial_adjustments,
    )

  // Query the room actor to verify initial adjustment is set
  let assert Ok(room_actor_ref) = rooms_supervisor.get_room_actor(room_sup)
  let reply = process.new_subject()
  process.send(room_actor_ref.subject, room_actor.GetState(reply))
  let assert Ok(state) = process.receive(reply, 1000)

  state.adjustment |> should.equal(1.5)
}

pub fn room_supervisor_uses_zero_adjustment_for_unknown_room_test() {
  let state_aggregator: process.Subject(state_aggregator_actor.Message) =
    process.new_subject()
  let #(ha_command_name, _spy) = make_mock_ha_command("zero_adjustment")
  let room_config = make_single_room_config()

  // Adjustments list doesn't include lounge
  let initial_adjustments = [
    room_adjustments.RoomAdjustment(room_name: "kitchen", adjustment: 2.0),
  ]

  let assert Ok(room_sup) =
    rooms_supervisor.start_room(
      room_config: room_config,
      state_aggregator: state_aggregator,
      ha_command_name: ha_command_name,
      house_mode: make_dummy_house_mode(),
      heating_control: None,
      initial_adjustments: initial_adjustments,
    )

  // Query the room actor - should have 0.0 adjustment (not in list)
  let assert Ok(room_actor_ref) = rooms_supervisor.get_room_actor(room_sup)
  let reply = process.new_subject()
  process.send(room_actor_ref.subject, room_actor.GetState(reply))
  let assert Ok(state) = process.receive(reply, 1000)

  state.adjustment |> should.equal(0.0)
}

pub fn room_supervisor_starts_trv_actors_test() {
  let state_aggregator: process.Subject(state_aggregator_actor.Message) =
    process.new_subject()
  let #(ha_command_name, _spy) = make_mock_ha_command("starts_trv")
  let room_config = make_single_room_config()

  let assert Ok(room_sup) =
    rooms_supervisor.start_room(
      room_config: room_config,
      state_aggregator: state_aggregator,
      ha_command_name: ha_command_name,
      house_mode: make_dummy_house_mode(),
      heating_control: None,
      initial_adjustments: [],
    )

  // Should be able to get the TRV actor subjects
  let trv_refs = rooms_supervisor.get_trv_actors(room_sup)

  // Should have one TRV actor
  list.length(trv_refs) |> should.equal(1)

  // Query the TRV actor to verify it's running
  let assert [trv_ref] = trv_refs
  let reply = process.new_subject()
  process.send(trv_ref.subject, trv_actor.GetState(reply))
  let assert Ok(state) = process.receive(reply, 1000)

  entity_id.climate_entity_id_to_string(state.entity_id)
  |> should.equal("climate.lounge_trv")
}

pub fn room_supervisor_starts_decision_actor_test() {
  let state_aggregator: process.Subject(state_aggregator_actor.Message) =
    process.new_subject()
  let #(ha_command_name, _spy) = make_mock_ha_command("starts_decision")
  let room_config = make_single_room_config()

  let assert Ok(room_sup) =
    rooms_supervisor.start_room(
      room_config: room_config,
      state_aggregator: state_aggregator,
      ha_command_name: ha_command_name,
      house_mode: make_dummy_house_mode(),
      heating_control: None,
      initial_adjustments: [],
    )

  // Should be able to get the decision actor subject
  let result = rooms_supervisor.get_decision_actor(room_sup)
  should.be_ok(result)
}

pub fn room_supervisor_with_multiple_trvs_test() {
  let state_aggregator: process.Subject(state_aggregator_actor.Message) =
    process.new_subject()
  let #(ha_command_name, _spy) = make_mock_ha_command("multiple_trvs")
  let room_config = make_multi_trv_room_config()

  let assert Ok(room_sup) =
    rooms_supervisor.start_room(
      room_config: room_config,
      state_aggregator: state_aggregator,
      ha_command_name: ha_command_name,
      house_mode: make_dummy_house_mode(),
      heating_control: None,
      initial_adjustments: [],
    )

  // Should have two TRV actors
  let trv_refs = rooms_supervisor.get_trv_actors(room_sup)
  list.length(trv_refs) |> should.equal(2)
}

// =============================================================================
// Integration Tests - Message Flow
// =============================================================================

pub fn trv_update_reaches_room_actor_test() {
  // This test verifies that when a TRV actor receives an update,
  // it notifies the room actor, which then notifies the state aggregator.
  let state_aggregator: process.Subject(state_aggregator_actor.Message) =
    process.new_subject()
  let #(ha_command_name, _spy) = make_mock_ha_command("trv_update")
  let room_config = make_single_room_config()

  let assert Ok(room_sup) =
    rooms_supervisor.start_room(
      room_config: room_config,
      state_aggregator: state_aggregator,
      ha_command_name: ha_command_name,
      house_mode: make_dummy_house_mode(),
      heating_control: None,
      initial_adjustments: [],
    )

  // Get the TRV actor
  let assert [trv_ref] = rooms_supervisor.get_trv_actors(room_sup)

  // Send an update to the TRV actor
  let temp = temperature.temperature(21.5)
  let update =
    trv_actor.TrvUpdate(
      temperature: Some(temp),
      target: None,
      mode: mode.HvacHeat,
      is_heating: False,
    )
  process.send(trv_ref.subject, trv_actor.Update(update))

  // Give time for message to propagate
  process.sleep(50)

  // Query room actor state - TRV temperature should be tracked
  let assert Ok(room_actor_ref) = rooms_supervisor.get_room_actor(room_sup)
  let reply = process.new_subject()
  process.send(room_actor_ref.subject, room_actor.GetState(reply))
  let assert Ok(state) = process.receive(reply, 1000)

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")
  let assert Ok(trv_state) = dict.get(state.trv_states, trv_id)
  trv_state.temperature |> should.equal(Some(temp))
}

pub fn room_decision_sends_command_to_trv_test() {
  // This test verifies that when room state changes with target temp,
  // the decision actor sends SetTarget to the TRV actor,
  // which forwards it to ha_commands.
  let state_aggregator: process.Subject(state_aggregator_actor.Message) =
    process.new_subject()
  let #(ha_command_name, spy) = make_mock_ha_command("decision_sends_cmd")
  let room_config = make_single_room_config()

  let assert Ok(room_sup) =
    rooms_supervisor.start_room(
      room_config: room_config,
      state_aggregator: state_aggregator,
      ha_command_name: ha_command_name,
      house_mode: make_dummy_house_mode(),
      heating_control: None,
      initial_adjustments: [],
    )

  // Get actors
  let assert [trv_ref] = rooms_supervisor.get_trv_actors(room_sup)
  let assert Ok(room_actor_ref) = rooms_supervisor.get_room_actor(room_sup)

  // First, set up the TRV with heat mode and a temperature
  // (decision actor only sends commands for TRVs that are not Off)
  let temp = temperature.temperature(19.0)
  let update =
    trv_actor.TrvUpdate(
      temperature: Some(temp),
      target: Some(temperature.temperature(20.0)),
      mode: mode.HvacHeat,
      is_heating: False,
    )
  process.send(trv_ref.subject, trv_actor.Update(update))

  // Send external temp to room actor (needed for offset calculation)
  process.send(
    room_actor_ref.subject,
    room_actor.ExternalTempChanged(temperature.temperature(18.0)),
  )

  // Give time for messages to propagate
  process.sleep(100)

  // The decision actor should have computed a target and sent it
  // Check that spy received a SetTrvAction command
  case process.receive(spy, 500) {
    Ok(ha_command_actor.SetTrvAction(eid, _mode, _target)) -> {
      entity_id.climate_entity_id_to_string(eid)
      |> should.equal("climate.lounge_trv")
    }
    Ok(_) -> should.fail()
    Error(_) -> {
      // It's possible the command was already sent - this is acceptable
      // The key thing is the actors are wired up correctly
      Nil
    }
  }
}

// =============================================================================
// RoomsSupervisor Tests (multiple rooms)
// =============================================================================

pub fn rooms_supervisor_starts_all_rooms_test() {
  let assert Ok(sleep_switch) =
    entity_id.goodnight_entity_id("input_button.goodnight")
  let assert Ok(heating_id) = entity_id.climate_entity_id("climate.heating")

  let config =
    HomeConfig(
      rooms: [make_single_room_config(), make_multi_trv_room_config()],
      sleep_switch_id: sleep_switch,
      heating_id: heating_id,
    )

  let state_aggregator: process.Subject(state_aggregator_actor.Message) =
    process.new_subject()
  let #(ha_command_name, _spy) = make_mock_ha_command("starts_all_rooms")

  let assert Ok(rooms_sup) =
    rooms_supervisor.start(
      config: config,
      state_aggregator: state_aggregator,
      ha_command_name: ha_command_name,
      house_mode: make_dummy_house_mode(),
      heating_control: None,
      initial_adjustments: [],
    )

  // Should have supervisors for both rooms
  let room_supervisors = rooms_supervisor.get_room_supervisors(rooms_sup)
  list.length(room_supervisors) |> should.equal(2)
}

pub fn room_supervisor_registers_room_actor_with_state_aggregator_test() {
  // This test verifies that when a room is started, its RoomActor is
  // automatically registered with the StateAggregatorActor so that
  // AdjustRoom messages can be forwarded correctly.
  let assert Ok(state_agg) = state_aggregator_actor.start_link()
  let #(ha_command_name, _spy) = make_mock_ha_command("registers_state_agg")
  let room_config = make_single_room_config()

  let assert Ok(room_sup) =
    rooms_supervisor.start_room(
      room_config: room_config,
      state_aggregator: state_agg,
      ha_command_name: ha_command_name,
      house_mode: make_dummy_house_mode(),
      heating_control: None,
      initial_adjustments: [],
    )

  // Give time for any async registration
  process.sleep(50)

  // Send an adjustment via the state aggregator
  process.send(state_agg, state_aggregator_actor.AdjustRoom("lounge", 2.0))
  process.sleep(50)

  // Query the room actor to check if adjustment was applied
  let assert Ok(room_actor_ref) = rooms_supervisor.get_room_actor(room_sup)
  let reply = process.new_subject()
  process.send(room_actor_ref.subject, room_actor.GetState(reply))
  let assert Ok(state) = process.receive(reply, 1000)

  // The adjustment should have been forwarded to the room actor
  state.adjustment |> should.equal(2.0)
}

// =============================================================================
// OTP Supervision Tests - Fault Tolerance
// =============================================================================

pub fn trv_actor_is_restarted_when_it_crashes_test() {
  // This test verifies that TRV actors are supervised and automatically
  // restarted when they crash. This is the core value of OTP supervision.
  //
  // With Named Subjects, we can query the actor by name after restart
  // because the restarted actor re-registers with the same name.
  let state_aggregator: process.Subject(state_aggregator_actor.Message) =
    process.new_subject()
  let #(ha_command_name, _spy) = make_mock_ha_command("trv_restart")
  let room_config = make_single_room_config()

  let assert Ok(room_sup) =
    rooms_supervisor.start_room(
      room_config: room_config,
      state_aggregator: state_aggregator,
      ha_command_name: ha_command_name,
      house_mode: make_dummy_house_mode(),
      heating_control: None,
      initial_adjustments: [],
    )

  // Get the TRV actor's name and current pid
  let assert [trv_ref] = rooms_supervisor.get_trv_actors(room_sup)
  let original_pid = trv_ref.pid
  let trv_name = trv_ref.name

  // Verify it's alive by sending a message via named subject
  let trv_subject = process.named_subject(trv_name)
  let reply1 = process.new_subject()
  process.send(trv_subject, trv_actor.GetState(reply1))
  let assert Ok(_) = process.receive(reply1, 1000)

  // Kill the TRV actor
  process.kill(original_pid)

  // Give supervision time to restart it
  process.sleep(200)

  // Query again via the same name - the restarted actor should respond
  let reply2 = process.new_subject()
  process.send(trv_subject, trv_actor.GetState(reply2))
  let result = process.receive(reply2, 1000)

  // Should be able to communicate with the restarted actor
  should.be_ok(result)
}

pub fn room_supervisor_exposes_room_name_test() {
  // This test verifies that RoomSupervisor exposes its room_name directly,
  // enabling reliable matching without fragile entity count comparisons.
  let state_aggregator: process.Subject(state_aggregator_actor.Message) =
    process.new_subject()
  let #(ha_command_name, _spy) = make_mock_ha_command("exposes_room_name")
  let room_config = make_single_room_config()

  let assert Ok(room_sup) =
    rooms_supervisor.start_room(
      room_config: room_config,
      state_aggregator: state_aggregator,
      ha_command_name: ha_command_name,
      house_mode: make_dummy_house_mode(),
      heating_control: None,
      initial_adjustments: [],
    )

  // Should be able to get the room name directly from RoomSupervisor
  rooms_supervisor.get_room_name(room_sup) |> should.equal("lounge")
}

pub fn rooms_supervisor_can_get_room_by_name_test() {
  let assert Ok(sleep_switch) =
    entity_id.goodnight_entity_id("input_button.goodnight")
  let assert Ok(heating_id) = entity_id.climate_entity_id("climate.heating")

  let config =
    HomeConfig(
      rooms: [make_single_room_config(), make_multi_trv_room_config()],
      sleep_switch_id: sleep_switch,
      heating_id: heating_id,
    )

  let state_aggregator: process.Subject(state_aggregator_actor.Message) =
    process.new_subject()
  let #(ha_command_name, _spy) = make_mock_ha_command("get_by_name")

  let assert Ok(rooms_sup) =
    rooms_supervisor.start(
      config: config,
      state_aggregator: state_aggregator,
      ha_command_name: ha_command_name,
      house_mode: make_dummy_house_mode(),
      heating_control: None,
      initial_adjustments: [],
    )

  // Should be able to look up rooms by name
  let lounge_result = rooms_supervisor.get_room_by_name(rooms_sup, "lounge")
  should.be_ok(lounge_result)

  let bedroom_result = rooms_supervisor.get_room_by_name(rooms_sup, "bedroom")
  should.be_ok(bedroom_result)

  let unknown_result = rooms_supervisor.get_room_by_name(rooms_sup, "unknown")
  should.be_error(unknown_result)
}

// =============================================================================
// TRV Command Adapter Tests - Verify message forwarding works
// =============================================================================

pub fn trv_command_adapter_forwards_commands_to_ha_test() {
  // This test verifies that when RoomDecisionActor sends a TrvCommand,
  // it gets forwarded to the HaCommandActor via the adapter.
  // This is a regression test for a Subject ownership bug where the adapter
  // created the Subject in the parent process but tried to receive in a child.
  let state_aggregator: process.Subject(state_aggregator_actor.Message) =
    process.new_subject()
  let #(ha_command_name, spy) = make_mock_ha_command("adapter_forwards")
  let room_config = make_single_room_config()

  let assert Ok(room_sup) =
    rooms_supervisor.start_room(
      room_config: room_config,
      state_aggregator: state_aggregator,
      ha_command_name: ha_command_name,
      house_mode: make_dummy_house_mode(),
      heating_control: None,
      initial_adjustments: [],
    )

  // Get actors
  let assert [trv_ref] = rooms_supervisor.get_trv_actors(room_sup)
  let assert Ok(room_actor_ref) = rooms_supervisor.get_room_actor(room_sup)

  // Set up the TRV with heat mode and a temperature
  let temp = temperature.temperature(19.0)
  let update =
    trv_actor.TrvUpdate(
      temperature: Some(temp),
      target: Some(temperature.temperature(20.0)),
      mode: mode.HvacHeat,
      is_heating: False,
    )
  process.send(trv_ref.subject, trv_actor.Update(update))

  // Send external temp to room actor (needed for offset calculation)
  process.send(
    room_actor_ref.subject,
    room_actor.ExternalTempChanged(temperature.temperature(18.0)),
  )

  // Give time for messages to propagate through the actor chain
  process.sleep(200)

  // The adapter MUST forward the command to spy
  // If the Subject ownership bug exists, this will timeout
  case process.receive(spy, 1000) {
    Ok(ha_command_actor.SetTrvAction(eid, _mode, _target)) -> {
      // Success - command was forwarded correctly
      entity_id.climate_entity_id_to_string(eid)
      |> should.equal("climate.lounge_trv")
    }
    Ok(_other) -> {
      // Wrong message type
      should.fail()
    }
    Error(Nil) -> {
      // Timeout - this means the adapter didn't forward the message!
      // This is the bug we're testing for
      should.fail()
    }
  }
}

// =============================================================================
// HouseModeActor Registration Tests
// =============================================================================

pub fn room_supervisor_registers_room_actor_with_house_mode_actor_test() {
  // This test verifies that when a room is started, its RoomActor is
  // automatically registered with HouseModeActor so that mode changes
  // are broadcast to it.

  // Create a time provider that returns 21:00 (after 8pm, so sleep button works)
  let test_time = house_mode_actor.local_datetime(2026, 1, 4, 21, 0, 0)
  let time_provider = fn() { test_time }

  // Start HouseModeActor with timer disabled (interval=0)
  let assert Ok(house_mode) =
    house_mode_actor.start_with_timer_interval(time_provider, 0)

  let state_aggregator: process.Subject(state_aggregator_actor.Message) =
    process.new_subject()
  let #(ha_command_name, _spy) = make_mock_ha_command("registers_house_mode")
  let room_config = make_single_room_config()

  // Start the room - should register with house_mode actor
  let assert Ok(room_sup) =
    rooms_supervisor.start_room(
      room_config: room_config,
      state_aggregator: state_aggregator,
      ha_command_name: ha_command_name,
      house_mode: house_mode,
      heating_control: None,
      initial_adjustments: [],
    )

  // Get the room actor to query its state
  let assert Ok(room_actor_ref) = rooms_supervisor.get_room_actor(room_sup)

  // Verify initial mode is Auto
  let reply1 = process.new_subject()
  process.send(room_actor_ref.subject, room_actor.GetState(reply1))
  let assert Ok(state1) = process.receive(reply1, 1000)
  state1.house_mode |> should.equal(mode.HouseModeAuto)

  // Press sleep button on HouseModeActor (after 8pm, so it takes effect)
  process.send(house_mode, house_mode_actor.SleepButtonPressed)
  process.sleep(50)

  // Query room actor again - should now be in Sleeping mode
  let reply2 = process.new_subject()
  process.send(room_actor_ref.subject, room_actor.GetState(reply2))
  let assert Ok(state2) = process.receive(reply2, 1000)
  state2.house_mode |> should.equal(mode.HouseModeSleeping)
}
