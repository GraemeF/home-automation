import deep_heating/actor/event_router_actor
import deep_heating/actor/ha_poller_actor
import deep_heating/actor/house_mode_actor
import deep_heating/actor/trv_actor
import deep_heating/entity_id
import deep_heating/mode
import deep_heating/temperature
import gleam/dict
import gleam/erlang/process
import gleam/option.{None, Some}
import gleeunit/should

// =============================================================================
// Test Helpers
// =============================================================================

/// Create an empty TRV registry for tests that don't need TRV routing
fn empty_trv_registry() -> event_router_actor.TrvActorRegistry {
  event_router_actor.build_trv_registry(dict.new())
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

  // Create a mock room actor to receive notifications from TrvActor
  let room_actor_spy: process.Subject(trv_actor.RoomMessage) =
    process.new_subject()

  // Create the entity_id we'll be updating
  let assert Ok(lounge_trv) = entity_id.climate_entity_id("climate.lounge_trv")

  // Start TrvActor
  let trv_name = process.new_name("trv_actor_lounge")
  let assert Ok(trv_started) =
    trv_actor.start(lounge_trv, trv_name, room_actor_spy)

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
