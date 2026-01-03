import deep_heating/actor/ha_poller_actor
import deep_heating/entity_id
import deep_heating/home_assistant
import gleam/erlang/process
import gleam/list
import gleam/set
import gleeunit/should

// =============================================================================
// Test Helpers
// =============================================================================

fn create_test_config() -> ha_poller_actor.PollerConfig {
  let assert Ok(heating_id) = entity_id.climate_entity_id("climate.main")
  let assert Ok(trv1) = entity_id.climate_entity_id("climate.lounge_trv")
  let assert Ok(trv2) = entity_id.climate_entity_id("climate.bedroom_trv")

  ha_poller_actor.PollerConfig(
    poll_interval_ms: 100,
    heating_entity_id: heating_id,
    sleep_button_entity_id: "input_button.goodnight",
    managed_trv_ids: set.from_list([trv1, trv2]),
  )
}

// =============================================================================
// Actor Startup Tests
// =============================================================================

pub fn ha_poller_actor_starts_successfully_test() {
  // HaPollerActor should start successfully
  let event_spy: process.Subject(ha_poller_actor.PollerEvent) =
    process.new_subject()
  let config = create_test_config()

  let result =
    ha_poller_actor.start(
      ha_client: home_assistant.HaClient("http://localhost:8123", "test-token"),
      config: config,
      event_spy: event_spy,
    )

  should.be_ok(result)
}

// =============================================================================
// Polling Control Tests
// =============================================================================

pub fn emits_polling_started_when_start_polling_received_test() {
  // When StartPolling is received, should emit PollingStarted event
  let event_spy: process.Subject(ha_poller_actor.PollerEvent) =
    process.new_subject()
  let config = create_test_config()

  let assert Ok(started) =
    ha_poller_actor.start(
      ha_client: home_assistant.HaClient("http://localhost:8123", "test-token"),
      config: config,
      event_spy: event_spy,
    )

  // Send StartPolling message
  process.send(started.data, ha_poller_actor.StartPolling)

  // Should receive PollingStarted event
  let assert Ok(event) = process.receive(event_spy, 100)
  case event {
    ha_poller_actor.PollingStarted -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn emits_polling_stopped_when_stop_polling_received_test() {
  // When StopPolling is received while polling, should emit PollingStopped event
  let event_spy: process.Subject(ha_poller_actor.PollerEvent) =
    process.new_subject()
  let config = create_test_config()

  let assert Ok(started) =
    ha_poller_actor.start(
      ha_client: home_assistant.HaClient("http://localhost:8123", "test-token"),
      config: config,
      event_spy: event_spy,
    )

  // Start polling first
  process.send(started.data, ha_poller_actor.StartPolling)
  // Consume PollingStarted
  let assert Ok(_) = process.receive(event_spy, 100)

  // Drain any poll events that happened
  drain_poll_events(event_spy)

  // Send StopPolling message
  process.send(started.data, ha_poller_actor.StopPolling)

  // Should receive PollingStopped event
  let assert Ok(event) = process.receive(event_spy, 100)
  case event {
    ha_poller_actor.PollingStopped -> should.be_true(True)
    _ -> should.fail()
  }
}

/// Drain any poll completion events from the spy
fn drain_poll_events(spy: process.Subject(ha_poller_actor.PollerEvent)) -> Nil {
  case process.receive(spy, 50) {
    Ok(ha_poller_actor.PollCompleted) -> drain_poll_events(spy)
    Ok(ha_poller_actor.PollFailed(_)) -> drain_poll_events(spy)
    _ -> Nil
  }
}

pub fn schedules_first_poll_immediately_when_start_polling_received_test() {
  // When StartPolling is received, should schedule PollNow immediately
  // This triggers the first poll right away
  let event_spy: process.Subject(ha_poller_actor.PollerEvent) =
    process.new_subject()
  // Short interval for fast test
  let assert Ok(heating_id) = entity_id.climate_entity_id("climate.main")
  let config =
    ha_poller_actor.PollerConfig(
      poll_interval_ms: 50,
      heating_entity_id: heating_id,
      sleep_button_entity_id: "input_button.goodnight",
      managed_trv_ids: set.new(),
    )

  let assert Ok(started) =
    ha_poller_actor.start(
      ha_client: home_assistant.HaClient("http://localhost:8123", "test-token"),
      config: config,
      event_spy: event_spy,
    )

  // Send StartPolling message
  process.send(started.data, ha_poller_actor.StartPolling)

  // Should receive PollingStarted, then either PollCompleted or PollFailed
  // (depending on whether the HA server is running)
  let assert Ok(ha_poller_actor.PollingStarted) =
    process.receive(event_spy, 100)

  // Wait for poll to execute (should happen quickly)
  let assert Ok(poll_event) = process.receive(event_spy, 200)

  // Should receive a poll result event (either success or failure is OK)
  case poll_event {
    ha_poller_actor.PollCompleted -> should.be_true(True)
    ha_poller_actor.PollFailed(_) -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn does_not_poll_when_not_started_test() {
  // Actor should not poll until StartPolling is received
  let event_spy: process.Subject(ha_poller_actor.PollerEvent) =
    process.new_subject()
  let config = create_test_config()

  let assert Ok(_started) =
    ha_poller_actor.start(
      ha_client: home_assistant.HaClient("http://localhost:8123", "test-token"),
      config: config,
      event_spy: event_spy,
    )

  // Wait a bit - should not receive any events
  process.sleep(150)
  let result = process.receive(event_spy, 50)
  result |> should.be_error
}

// =============================================================================
// Entity Parsing Tests (via mock JSON injection)
// =============================================================================

pub fn dispatches_trv_update_for_managed_trvs_test() {
  // When polling succeeds and returns climate entities,
  // should dispatch TrvUpdated events for managed TRVs
  let event_spy: process.Subject(ha_poller_actor.PollerEvent) =
    process.new_subject()

  let assert Ok(trv1) = entity_id.climate_entity_id("climate.lounge_trv")
  let config =
    ha_poller_actor.PollerConfig(
      poll_interval_ms: 5000,
      heating_entity_id: trv1,
      sleep_button_entity_id: "input_button.goodnight",
      managed_trv_ids: set.from_list([trv1]),
    )

  let assert Ok(started) =
    ha_poller_actor.start(
      ha_client: home_assistant.HaClient("http://localhost:8123", "test-token"),
      config: config,
      event_spy: event_spy,
    )

  // Inject mock JSON response
  let mock_json =
    "[{\"entity_id\":\"climate.lounge_trv\",\"state\":\"heat\",\"attributes\":{\"current_temperature\":20.5,\"temperature\":21.0,\"hvac_action\":\"heating\"}}]"
  process.send(started.data, ha_poller_actor.InjectMockResponse(mock_json))

  // Trigger a poll
  process.send(started.data, ha_poller_actor.PollNow)

  // Should receive a TrvUpdated event
  let events = collect_events(event_spy, 3, 500)

  // Check we got a TrvUpdated event for the managed TRV
  let has_trv_update =
    list.any(events, fn(event) {
      case event {
        ha_poller_actor.TrvUpdated(eid, _update) -> eid == trv1
        _ -> False
      }
    })

  has_trv_update |> should.be_true
}

pub fn filters_unmanaged_trvs_test() {
  // TRVs not in the managed_trv_ids set should NOT be dispatched
  let event_spy: process.Subject(ha_poller_actor.PollerEvent) =
    process.new_subject()

  let assert Ok(managed_trv) =
    entity_id.climate_entity_id("climate.managed_trv")
  let assert Ok(unmanaged_trv) =
    entity_id.climate_entity_id("climate.unmanaged_trv")

  let config =
    ha_poller_actor.PollerConfig(
      poll_interval_ms: 5000,
      heating_entity_id: managed_trv,
      sleep_button_entity_id: "input_button.goodnight",
      // Only the managed TRV is in the set
      managed_trv_ids: set.from_list([managed_trv]),
    )

  let assert Ok(started) =
    ha_poller_actor.start(
      ha_client: home_assistant.HaClient("http://localhost:8123", "test-token"),
      config: config,
      event_spy: event_spy,
    )

  // Inject mock JSON with both TRVs
  let mock_json =
    "[{\"entity_id\":\"climate.managed_trv\",\"state\":\"heat\",\"attributes\":{\"current_temperature\":20.0,\"temperature\":21.0,\"hvac_action\":\"idle\"}},{\"entity_id\":\"climate.unmanaged_trv\",\"state\":\"heat\",\"attributes\":{\"current_temperature\":18.0,\"temperature\":19.0,\"hvac_action\":\"idle\"}}]"
  process.send(started.data, ha_poller_actor.InjectMockResponse(mock_json))

  // Trigger a poll
  process.send(started.data, ha_poller_actor.PollNow)

  // Collect events
  let events = collect_events(event_spy, 5, 500)

  // Should have TrvUpdated for managed TRV
  let has_managed =
    list.any(events, fn(event) {
      case event {
        ha_poller_actor.TrvUpdated(eid, _) -> eid == managed_trv
        _ -> False
      }
    })

  // Should NOT have TrvUpdated for unmanaged TRV
  let has_unmanaged =
    list.any(events, fn(event) {
      case event {
        ha_poller_actor.TrvUpdated(eid, _) -> eid == unmanaged_trv
        _ -> False
      }
    })

  has_managed |> should.be_true
  has_unmanaged |> should.be_false
}

/// Collect events from the spy for up to max_events or until timeout
fn collect_events(
  spy: process.Subject(ha_poller_actor.PollerEvent),
  max_events: Int,
  timeout_ms: Int,
) -> List(ha_poller_actor.PollerEvent) {
  collect_events_loop(spy, max_events, timeout_ms, [])
}

fn collect_events_loop(
  spy: process.Subject(ha_poller_actor.PollerEvent),
  remaining: Int,
  timeout_ms: Int,
  acc: List(ha_poller_actor.PollerEvent),
) -> List(ha_poller_actor.PollerEvent) {
  case remaining <= 0 {
    True -> list.reverse(acc)
    False -> {
      case process.receive(spy, timeout_ms) {
        Ok(event) ->
          collect_events_loop(spy, remaining - 1, timeout_ms, [event, ..acc])
        Error(_) -> list.reverse(acc)
      }
    }
  }
}
