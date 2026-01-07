import deep_heating/entity_id
import deep_heating/event_router_actor
import deep_heating/heating/heating_control_actor
import deep_heating/home_assistant/ha_poller_actor
import deep_heating/house_mode/house_mode_actor
import deep_heating/mode
import deep_heating/rooms/room_actor
import deep_heating/rooms/trv_actor
import deep_heating/scheduling/schedule as deep_heating_schedule
import deep_heating/temperature
import gleam/dict
import gleam/erlang/process.{type Name, type Subject}
import gleam/int
import gleam/option.{None, Some}
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

/// Create a mock RoomDecisionActor that uses actor.named() and forwards to a spy.
/// Returns the actor name and spy Subject for receiving messages.
fn make_mock_decision_actor(
  test_id: String,
) -> #(Name(room_actor.DecisionMessage), Subject(room_actor.DecisionMessage)) {
  let spy = process.new_subject()
  let name =
    process.new_name(
      "mock_decision_" <> test_id <> "_" <> int.to_string(unique_integer()),
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

/// Create a mock RoomActor that uses actor.named() and forwards to a spy.
/// Returns the actor name and spy Subject for receiving messages.
/// This is used by TrvActor tests which need a named RoomActor.
fn make_mock_room_actor_for_trv(
  test_id: String,
) -> #(Name(trv_actor.RoomMessage), Subject(trv_actor.RoomMessage)) {
  let spy = process.new_subject()
  let name =
    process.new_name(
      "mock_room_for_trv_" <> test_id <> "_" <> int.to_string(unique_integer()),
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

/// Create an empty TRV registry for tests that don't need TRV routing
fn empty_trv_registry() -> event_router_actor.TrvActorRegistry {
  event_router_actor.build_trv_registry(dict.new())
}

/// Create an empty sensor registry for tests that don't need sensor routing
fn empty_sensor_registry() -> event_router_actor.SensorRegistry {
  event_router_actor.build_sensor_registry(dict.new())
}

// =============================================================================
// Actor Startup Tests
// =============================================================================

pub fn event_router_actor_starts_successfully_test() {
  // EventRouterActor should start successfully with valid config
  let assert Ok(house_mode) =
    house_mode_actor.start_with_timer_interval(
      fn() { house_mode_actor.local_datetime(2026, 1, 4, 12, 0, 0) },
      0,
    )

  let config =
    event_router_actor.Config(
      house_mode_actor: house_mode,
      trv_registry: empty_trv_registry(),
      sensor_registry: empty_sensor_registry(),
      heating_control_actor: None,
    )

  let result = event_router_actor.start(config)

  should.be_ok(result)
}

// =============================================================================
// SleepButtonPressed Routing Tests
// =============================================================================

pub fn routes_sleep_button_pressed_to_house_mode_actor_test() {
  // When a SleepButtonPressed event is received, it should be forwarded
  // to the HouseModeActor

  // Start HouseModeActor with time after 8pm so button press is accepted
  let assert Ok(house_mode) =
    house_mode_actor.start_with_timer_interval(
      fn() { house_mode_actor.local_datetime(2026, 1, 4, 21, 30, 0) },
      0,
    )

  let config =
    event_router_actor.Config(
      house_mode_actor: house_mode,
      trv_registry: empty_trv_registry(),
      sensor_registry: empty_sensor_registry(),
      heating_control_actor: None,
    )

  // Start router - it returns the subject to send events to
  let assert Ok(router_subject) = event_router_actor.start(config)

  // Get initial mode (should be Auto at 21:30)
  let reply_to = process.new_subject()
  process.send(house_mode, house_mode_actor.GetMode(reply_to))
  let assert Ok(initial_mode) = process.receive(reply_to, 100)
  initial_mode |> should.equal(mode.HouseModeAuto)

  // Send SleepButtonPressed event to the router
  process.send(router_subject, ha_poller_actor.SleepButtonPressed)

  // Give it a moment to process
  process.sleep(100)

  // Verify HouseModeActor received the message and changed to Sleeping
  process.send(house_mode, house_mode_actor.GetMode(reply_to))
  let assert Ok(new_mode) = process.receive(reply_to, 100)
  new_mode |> should.equal(mode.HouseModeSleeping)
}

// =============================================================================
// TrvUpdated Routing Tests
// =============================================================================

pub fn routes_trv_updated_to_correct_trv_actor_test() {
  // When a TrvUpdated event is received, it should be routed to the
  // correct TrvActor based on entity_id → subject mapping

  // Create a mock named room actor to receive notifications from TrvActor
  let #(room_actor_name, room_actor_spy) =
    make_mock_room_actor_for_trv("trv_routing")

  // Create the entity_id we'll be updating
  let assert Ok(lounge_trv) = entity_id.climate_entity_id("climate.lounge_trv")

  // Start TrvActor - now takes a Name instead of Subject
  let trv_name = process.new_name("trv_actor_lounge")
  let assert Ok(trv_started) =
    trv_actor.start(lounge_trv, trv_name, room_actor_name)

  // Build registry with the TrvActor's subject
  let trv_registry =
    event_router_actor.build_trv_registry(
      dict.from_list([#(lounge_trv, trv_started.data)]),
    )

  // Start HouseModeActor (required for config)
  let assert Ok(house_mode) =
    house_mode_actor.start_with_timer_interval(
      fn() { house_mode_actor.local_datetime(2026, 1, 4, 12, 0, 0) },
      0,
    )

  let config =
    event_router_actor.Config(
      house_mode_actor: house_mode,
      trv_registry: trv_registry,
      sensor_registry: empty_sensor_registry(),
      heating_control_actor: None,
    )

  // Start router - it returns the subject to send events to
  let assert Ok(router_subject) = event_router_actor.start(config)

  // Send TrvUpdated event to router
  let update =
    trv_actor.TrvUpdate(
      temperature: Some(temperature.temperature(21.5)),
      target: Some(temperature.temperature(22.0)),
      mode: mode.HvacHeat,
      is_heating: True,
    )
  process.send(router_subject, ha_poller_actor.TrvUpdated(lounge_trv, update))

  // Give it a moment to process
  process.sleep(100)

  // The TrvActor should have notified the room actor of the temperature change
  let assert Ok(room_message) = process.receive(room_actor_spy, 500)
  case room_message {
    trv_actor.TrvTemperatureChanged(entity_id, _temp) ->
      entity_id |> should.equal(lounge_trv)
    _ -> should.fail()
  }
}

pub fn ignores_trv_updated_for_unknown_entity_test() {
  // When a TrvUpdated event is received for an entity not in the registry,
  // it should be silently ignored (no crash)

  let assert Ok(house_mode) =
    house_mode_actor.start_with_timer_interval(
      fn() { house_mode_actor.local_datetime(2026, 1, 4, 12, 0, 0) },
      0,
    )

  let config =
    event_router_actor.Config(
      house_mode_actor: house_mode,
      trv_registry: empty_trv_registry(),
      sensor_registry: empty_sensor_registry(),
      heating_control_actor: None,
    )

  let assert Ok(router_subject) = event_router_actor.start(config)

  // Send TrvUpdated for unknown entity
  let assert Ok(unknown_trv) =
    entity_id.climate_entity_id("climate.unknown_trv")
  let update =
    trv_actor.TrvUpdate(
      temperature: None,
      target: None,
      mode: mode.HvacOff,
      is_heating: False,
    )
  process.send(router_subject, ha_poller_actor.TrvUpdated(unknown_trv, update))

  // Give it a moment - should not crash
  process.sleep(50)

  // If we get here without crashing, the test passes
  should.be_true(True)
}

// =============================================================================
// Poll Status Event Tests
// =============================================================================

pub fn ignores_poll_completed_events_test() {
  // PollCompleted events should be ignored (not routed anywhere)

  let assert Ok(house_mode) =
    house_mode_actor.start_with_timer_interval(
      fn() { house_mode_actor.local_datetime(2026, 1, 4, 12, 0, 0) },
      0,
    )

  let config =
    event_router_actor.Config(
      house_mode_actor: house_mode,
      trv_registry: empty_trv_registry(),
      sensor_registry: empty_sensor_registry(),
      heating_control_actor: None,
    )

  let assert Ok(router_subject) = event_router_actor.start(config)

  // Send poll status events - should not crash
  process.send(router_subject, ha_poller_actor.PollCompleted)
  process.send(router_subject, ha_poller_actor.PollFailed("test error"))
  process.send(router_subject, ha_poller_actor.PollingStarted)
  process.send(router_subject, ha_poller_actor.PollingStopped)
  process.send(router_subject, ha_poller_actor.BackoffApplied(1000))
  process.send(router_subject, ha_poller_actor.BackoffReset)

  // Give it a moment
  process.sleep(50)

  // If we get here without crashing, the test passes
  should.be_true(True)
}

// =============================================================================
// SensorUpdated Routing Tests
// =============================================================================

pub fn routes_sensor_updated_to_correct_room_actor_test() {
  // When a SensorUpdated event is received, it should be routed to the
  // correct RoomActor based on sensor_id → room_actor mapping

  // Create a named mock decision actor and a spy for aggregator
  let #(decision_name, _decision_spy) =
    make_mock_decision_actor("sensor_routing")
  let aggregator_spy: Subject(room_actor.AggregatorMessage) =
    process.new_subject()

  // Create the sensor_id we'll be updating
  let assert Ok(lounge_sensor) =
    entity_id.sensor_entity_id("sensor.lounge_temperature")

  // Create a simple schedule for the room
  let schedule =
    deep_heating_schedule.WeekSchedule(
      monday: [],
      tuesday: [],
      wednesday: [],
      thursday: [],
      friday: [],
      saturday: [],
      sunday: [],
    )

  // Start RoomActor - uses decision_actor_name for named lookup
  let assert Ok(room_started) =
    room_actor.start(
      name: "lounge",
      schedule: schedule,
      decision_actor_name: decision_name,
      state_aggregator: aggregator_spy,
      heating_control: option.None,
    )

  // Consume initial state broadcast from RoomActor
  let assert Ok(_initial) = process.receive(aggregator_spy, 1000)

  // Build sensor registry with the RoomActor's subject
  let sensor_registry =
    event_router_actor.build_sensor_registry(
      dict.from_list([#(lounge_sensor, room_started.data)]),
    )

  // Start HouseModeActor (required for config)
  let assert Ok(house_mode) =
    house_mode_actor.start_with_timer_interval(
      fn() { house_mode_actor.local_datetime(2026, 1, 4, 12, 0, 0) },
      0,
    )

  let config =
    event_router_actor.Config(
      house_mode_actor: house_mode,
      trv_registry: empty_trv_registry(),
      sensor_registry: sensor_registry,
      heating_control_actor: None,
    )

  // Start router
  let assert Ok(router_subject) = event_router_actor.start(config)

  // Send SensorUpdated event to router
  process.send(
    router_subject,
    ha_poller_actor.SensorUpdated(
      lounge_sensor,
      Some(temperature.temperature(21.5)),
    ),
  )

  // Give it a moment to process
  process.sleep(100)

  // The RoomActor should have updated its state and notified the aggregator
  // Check the aggregator spy for RoomUpdated message
  let assert Ok(aggregator_message) = process.receive(aggregator_spy, 500)
  case aggregator_message {
    room_actor.RoomUpdated(name, room_state) -> {
      name |> should.equal("lounge")
      // The room should have received the temperature update (now wrapped in TemperatureReading)
      let expected_temp = temperature.temperature(21.5)
      case room_state.temperature {
        Some(reading) -> reading.temperature |> should.equal(expected_temp)
        None -> should.fail()
      }
    }
  }
}

pub fn ignores_sensor_updated_for_unknown_sensor_test() {
  // When a SensorUpdated event is received for a sensor not in the registry,
  // it should be silently ignored (no crash)

  let assert Ok(house_mode) =
    house_mode_actor.start_with_timer_interval(
      fn() { house_mode_actor.local_datetime(2026, 1, 4, 12, 0, 0) },
      0,
    )

  let config =
    event_router_actor.Config(
      house_mode_actor: house_mode,
      trv_registry: empty_trv_registry(),
      sensor_registry: empty_sensor_registry(),
      heating_control_actor: None,
    )

  let assert Ok(router_subject) = event_router_actor.start(config)

  // Send SensorUpdated for unknown sensor
  let assert Ok(unknown_sensor) =
    entity_id.sensor_entity_id("sensor.unknown_temp")
  process.send(
    router_subject,
    ha_poller_actor.SensorUpdated(
      unknown_sensor,
      Some(temperature.temperature(20.0)),
    ),
  )

  // Give it a moment - should not crash
  process.sleep(50)

  // If we get here without crashing, the test passes
  should.be_true(True)
}

// =============================================================================
// HeatingStatusChanged Routing Tests
// =============================================================================

pub fn routes_heating_status_changed_to_heating_control_actor_test() {
  // When a HeatingStatusChanged event is received, it should be routed to
  // the HeatingControlActor

  // Create a spy for boiler commands (domain interface for HeatingControlActor)
  let boiler_commands_spy: process.Subject(heating_control_actor.BoilerCommand) =
    process.new_subject()

  // Start HeatingControlActor
  let assert Ok(boiler_entity_id) =
    entity_id.climate_entity_id("climate.boiler")
  let assert Ok(heating_control_started) =
    heating_control_actor.start(
      boiler_entity_id: boiler_entity_id,
      boiler_commands: boiler_commands_spy,
    )

  // Start HouseModeActor (required for config)
  let assert Ok(house_mode) =
    house_mode_actor.start_with_timer_interval(
      fn() { house_mode_actor.local_datetime(2026, 1, 4, 12, 0, 0) },
      0,
    )

  let config =
    event_router_actor.Config(
      house_mode_actor: house_mode,
      trv_registry: empty_trv_registry(),
      sensor_registry: empty_sensor_registry(),
      heating_control_actor: Some(heating_control_started.data),
    )

  // Start router
  let assert Ok(router_subject) = event_router_actor.start(config)

  // Send HeatingStatusChanged event to router
  process.send(router_subject, ha_poller_actor.HeatingStatusChanged(True))

  // Give it a moment to process
  process.sleep(100)

  // Query HeatingControlActor state to verify it received the message
  let reply_subject = process.new_subject()
  process.send(
    heating_control_started.data,
    heating_control_actor.GetState(reply_subject),
  )

  let assert Ok(state) = process.receive(reply_subject, 1000)

  // The boiler_is_heating should have been updated to True by the routed message
  state.boiler_is_heating |> should.be_true
}
