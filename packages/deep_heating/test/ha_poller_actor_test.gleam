import deep_heating/actor/ha_poller_actor
import deep_heating/entity_id
import deep_heating/home_assistant
import deep_heating/temperature
import gleam/erlang/process
import gleam/list
import gleam/option.{Some}
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
    managed_sensor_ids: set.new(),
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

  // Use a long poll interval so no backoff polls interfere
  let assert Ok(heating_id) = entity_id.climate_entity_id("climate.main")
  let config =
    ha_poller_actor.PollerConfig(
      poll_interval_ms: 10_000,
      heating_entity_id: heating_id,
      sleep_button_entity_id: "input_button.goodnight",
      managed_trv_ids: set.new(),
      managed_sensor_ids: set.new(),
    )

  let assert Ok(started) =
    ha_poller_actor.start(
      ha_client: home_assistant.HaClient("http://localhost:8123", "test-token"),
      config: config,
      event_spy: event_spy,
    )

  // Inject empty mock response so poll completes instantly
  process.send(started.data, ha_poller_actor.InjectMockResponse("[]"))

  // Start polling
  process.send(started.data, ha_poller_actor.StartPolling)
  // Consume PollingStarted
  let assert Ok(ha_poller_actor.PollingStarted) =
    process.receive(event_spy, 100)

  // Drain poll completion events
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

/// Drain any poll completion/backoff events from the spy
fn drain_poll_events(spy: process.Subject(ha_poller_actor.PollerEvent)) -> Nil {
  case process.receive(spy, 200) {
    Ok(ha_poller_actor.PollCompleted) -> drain_poll_events(spy)
    Ok(ha_poller_actor.PollFailed(_)) -> drain_poll_events(spy)
    Ok(ha_poller_actor.BackoffApplied(_)) -> drain_poll_events(spy)
    Ok(ha_poller_actor.BackoffReset) -> drain_poll_events(spy)
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
      managed_sensor_ids: set.new(),
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
      managed_sensor_ids: set.new(),
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
      managed_sensor_ids: set.new(),
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

// =============================================================================
// Sleep Button Detection Tests
// =============================================================================

pub fn emits_sleep_button_pressed_when_state_changes_test() {
  // When the sleep button's state (timestamp) changes between polls,
  // should emit SleepButtonPressed event
  let event_spy: process.Subject(ha_poller_actor.PollerEvent) =
    process.new_subject()

  let assert Ok(heating_id) = entity_id.climate_entity_id("climate.main")
  let config =
    ha_poller_actor.PollerConfig(
      poll_interval_ms: 5000,
      heating_entity_id: heating_id,
      sleep_button_entity_id: "input_button.goodnight",
      managed_trv_ids: set.new(),
      managed_sensor_ids: set.new(),
    )

  let assert Ok(started) =
    ha_poller_actor.start(
      ha_client: home_assistant.HaClient("http://localhost:8123", "test-token"),
      config: config,
      event_spy: event_spy,
    )

  // First poll with initial timestamp
  let mock_json_1 =
    "[{\"entity_id\":\"input_button.goodnight\",\"state\":\"2026-01-03T10:00:00+00:00\",\"attributes\":{}}]"
  process.send(started.data, ha_poller_actor.InjectMockResponse(mock_json_1))
  process.send(started.data, ha_poller_actor.PollNow)

  // Wait for poll to complete
  let _ = collect_events(event_spy, 3, 500)

  // Second poll with DIFFERENT timestamp (button was pressed)
  let mock_json_2 =
    "[{\"entity_id\":\"input_button.goodnight\",\"state\":\"2026-01-03T10:05:00+00:00\",\"attributes\":{}}]"
  process.send(started.data, ha_poller_actor.InjectMockResponse(mock_json_2))
  process.send(started.data, ha_poller_actor.PollNow)

  // Collect events from second poll
  let events = collect_events(event_spy, 5, 500)

  // Should have received SleepButtonPressed event
  let has_sleep_button_pressed =
    list.any(events, fn(event) {
      case event {
        ha_poller_actor.SleepButtonPressed -> True
        _ -> False
      }
    })

  has_sleep_button_pressed |> should.be_true
}

pub fn does_not_emit_sleep_button_pressed_when_state_unchanged_test() {
  // When the sleep button's state is the same between polls,
  // should NOT emit SleepButtonPressed event
  let event_spy: process.Subject(ha_poller_actor.PollerEvent) =
    process.new_subject()

  let assert Ok(heating_id) = entity_id.climate_entity_id("climate.main")
  let config =
    ha_poller_actor.PollerConfig(
      poll_interval_ms: 5000,
      heating_entity_id: heating_id,
      sleep_button_entity_id: "input_button.goodnight",
      managed_trv_ids: set.new(),
      managed_sensor_ids: set.new(),
    )

  let assert Ok(started) =
    ha_poller_actor.start(
      ha_client: home_assistant.HaClient("http://localhost:8123", "test-token"),
      config: config,
      event_spy: event_spy,
    )

  // First poll with initial timestamp
  let mock_json =
    "[{\"entity_id\":\"input_button.goodnight\",\"state\":\"2026-01-03T10:00:00+00:00\",\"attributes\":{}}]"
  process.send(started.data, ha_poller_actor.InjectMockResponse(mock_json))
  process.send(started.data, ha_poller_actor.PollNow)

  // Wait for poll to complete
  let _ = collect_events(event_spy, 3, 500)

  // Second poll with SAME timestamp (button was NOT pressed)
  process.send(started.data, ha_poller_actor.InjectMockResponse(mock_json))
  process.send(started.data, ha_poller_actor.PollNow)

  // Collect events from second poll
  let events = collect_events(event_spy, 5, 500)

  // Should NOT have received SleepButtonPressed event
  let has_sleep_button_pressed =
    list.any(events, fn(event) {
      case event {
        ha_poller_actor.SleepButtonPressed -> True
        _ -> False
      }
    })

  has_sleep_button_pressed |> should.be_false
}

pub fn does_not_emit_sleep_button_pressed_on_first_poll_test() {
  // On first poll, should NOT emit SleepButtonPressed (just learn the state)
  let event_spy: process.Subject(ha_poller_actor.PollerEvent) =
    process.new_subject()

  let assert Ok(heating_id) = entity_id.climate_entity_id("climate.main")
  let config =
    ha_poller_actor.PollerConfig(
      poll_interval_ms: 5000,
      heating_entity_id: heating_id,
      sleep_button_entity_id: "input_button.goodnight",
      managed_trv_ids: set.new(),
      managed_sensor_ids: set.new(),
    )

  let assert Ok(started) =
    ha_poller_actor.start(
      ha_client: home_assistant.HaClient("http://localhost:8123", "test-token"),
      config: config,
      event_spy: event_spy,
    )

  // First poll - should NOT emit SleepButtonPressed
  let mock_json =
    "[{\"entity_id\":\"input_button.goodnight\",\"state\":\"2026-01-03T10:00:00+00:00\",\"attributes\":{}}]"
  process.send(started.data, ha_poller_actor.InjectMockResponse(mock_json))
  process.send(started.data, ha_poller_actor.PollNow)

  // Collect all events
  let events = collect_events(event_spy, 5, 500)

  // Should NOT have received SleepButtonPressed event
  let has_sleep_button_pressed =
    list.any(events, fn(event) {
      case event {
        ha_poller_actor.SleepButtonPressed -> True
        _ -> False
      }
    })

  has_sleep_button_pressed |> should.be_false
}

// =============================================================================
// Exponential Backoff Tests
// =============================================================================

pub fn schedules_next_poll_with_backoff_after_failure_test() {
  // When a poll fails, the next poll should be scheduled with exponential backoff
  // Base interval: 100ms, after first failure: 200ms (doubled)
  let event_spy: process.Subject(ha_poller_actor.PollerEvent) =
    process.new_subject()

  let assert Ok(heating_id) = entity_id.climate_entity_id("climate.main")
  let config =
    ha_poller_actor.PollerConfig(
      poll_interval_ms: 100,
      heating_entity_id: heating_id,
      sleep_button_entity_id: "input_button.goodnight",
      managed_trv_ids: set.new(),
      managed_sensor_ids: set.new(),
    )

  let assert Ok(started) =
    ha_poller_actor.start(
      ha_client: home_assistant.HaClient("http://localhost:8123", "test-token"),
      config: config,
      event_spy: event_spy,
    )

  // Inject an error for the first poll
  process.send(
    started.data,
    ha_poller_actor.InjectMockError(home_assistant.ConnectionError(
      "Connection refused",
    )),
  )

  // Start polling
  process.send(started.data, ha_poller_actor.StartPolling)

  // Expect: PollingStarted, then PollFailed
  let assert Ok(ha_poller_actor.PollingStarted) =
    process.receive(event_spy, 100)
  let assert Ok(ha_poller_actor.PollFailed(_)) = process.receive(event_spy, 100)

  // The backoff event should tell us the delay
  let assert Ok(ha_poller_actor.BackoffApplied(delay_ms)) =
    process.receive(event_spy, 100)

  // After first failure, backoff should be doubled from base (100 -> 200)
  delay_ms |> should.equal(200)
}

pub fn resets_backoff_after_successful_poll_test() {
  // After a successful poll, backoff should reset to base interval
  let event_spy: process.Subject(ha_poller_actor.PollerEvent) =
    process.new_subject()

  let assert Ok(heating_id) = entity_id.climate_entity_id("climate.main")
  let config =
    ha_poller_actor.PollerConfig(
      poll_interval_ms: 100,
      heating_entity_id: heating_id,
      sleep_button_entity_id: "input_button.goodnight",
      managed_trv_ids: set.new(),
      managed_sensor_ids: set.new(),
    )

  let assert Ok(started) =
    ha_poller_actor.start(
      ha_client: home_assistant.HaClient("http://localhost:8123", "test-token"),
      config: config,
      event_spy: event_spy,
    )

  // First: inject an error to build up backoff
  process.send(
    started.data,
    ha_poller_actor.InjectMockError(home_assistant.ConnectionError(
      "Connection refused",
    )),
  )
  process.send(started.data, ha_poller_actor.StartPolling)

  // Drain error events
  let _ = collect_events(event_spy, 5, 200)

  // Now inject a successful response
  let mock_json = "[]"
  process.send(started.data, ha_poller_actor.InjectMockResponse(mock_json))

  // Wait for the backoff poll to occur, then check the next scheduled delay
  // After success, should emit BackoffReset and use base interval
  let events = collect_events(event_spy, 5, 500)

  let has_backoff_reset =
    list.any(events, fn(event) {
      case event {
        ha_poller_actor.BackoffReset -> True
        _ -> False
      }
    })

  has_backoff_reset |> should.be_true
}

pub fn caps_backoff_at_max_value_test() {
  // Backoff should not exceed max value (60 seconds)
  let event_spy: process.Subject(ha_poller_actor.PollerEvent) =
    process.new_subject()

  let assert Ok(heating_id) = entity_id.climate_entity_id("climate.main")
  // Use a large base interval so doubling quickly exceeds max
  let config =
    ha_poller_actor.PollerConfig(
      poll_interval_ms: 30_000,
      heating_entity_id: heating_id,
      sleep_button_entity_id: "input_button.goodnight",
      managed_trv_ids: set.new(),
      managed_sensor_ids: set.new(),
    )

  let assert Ok(started) =
    ha_poller_actor.start(
      ha_client: home_assistant.HaClient("http://localhost:8123", "test-token"),
      config: config,
      event_spy: event_spy,
    )

  // Inject multiple errors to build up backoff
  // After 1st failure: 60000ms (30000 * 2)
  // After 2nd failure: would be 120000ms but capped at 60000ms
  process.send(
    started.data,
    ha_poller_actor.InjectMockError(home_assistant.ConnectionError(
      "Connection refused",
    )),
  )
  process.send(started.data, ha_poller_actor.PollNow)
  let _ = collect_events(event_spy, 3, 100)

  // Second failure
  process.send(
    started.data,
    ha_poller_actor.InjectMockError(home_assistant.ConnectionError(
      "Connection refused",
    )),
  )
  process.send(started.data, ha_poller_actor.PollNow)

  let events = collect_events(event_spy, 5, 200)

  // Find the BackoffApplied event and check it's capped at 60000ms
  let backoff_delays =
    list.filter_map(events, fn(event) {
      case event {
        ha_poller_actor.BackoffApplied(delay) -> Ok(delay)
        _ -> Error(Nil)
      }
    })

  // All backoff values should be <= 60000ms (max backoff)
  let all_capped = list.all(backoff_delays, fn(delay) { delay <= 60_000 })

  all_capped |> should.be_true
}

// =============================================================================
// Temperature Sensor Polling Tests
// =============================================================================

pub fn dispatches_sensor_update_for_managed_sensors_test() {
  // When polling succeeds and returns sensor entities,
  // should dispatch SensorUpdated events for managed sensors
  let event_spy: process.Subject(ha_poller_actor.PollerEvent) =
    process.new_subject()

  let assert Ok(heating_id) = entity_id.climate_entity_id("climate.main")
  let assert Ok(sensor1) =
    entity_id.sensor_entity_id("sensor.lounge_temperature")

  let config =
    ha_poller_actor.PollerConfig(
      poll_interval_ms: 5000,
      heating_entity_id: heating_id,
      sleep_button_entity_id: "input_button.goodnight",
      managed_trv_ids: set.new(),
      managed_sensor_ids: set.from_list([sensor1]),
    )

  let assert Ok(started) =
    ha_poller_actor.start(
      ha_client: home_assistant.HaClient("http://localhost:8123", "test-token"),
      config: config,
      event_spy: event_spy,
    )

  // Inject mock JSON response with a temperature sensor
  let mock_json =
    "[{\"entity_id\":\"sensor.lounge_temperature\",\"state\":\"21.5\",\"attributes\":{\"unit_of_measurement\":\"°C\"}}]"
  process.send(started.data, ha_poller_actor.InjectMockResponse(mock_json))

  // Trigger a poll
  process.send(started.data, ha_poller_actor.PollNow)

  // Should receive a SensorUpdated event
  let events = collect_events(event_spy, 5, 500)

  // Check we got a SensorUpdated event for the managed sensor
  let has_sensor_update =
    list.any(events, fn(event) {
      case event {
        ha_poller_actor.SensorUpdated(eid, temp) ->
          eid == sensor1 && temp == Some(temperature.temperature(21.5))
        _ -> False
      }
    })

  has_sensor_update |> should.be_true
}

pub fn filters_unmanaged_sensors_test() {
  // Sensors not in the managed_sensor_ids set should NOT be dispatched
  let event_spy: process.Subject(ha_poller_actor.PollerEvent) =
    process.new_subject()

  let assert Ok(heating_id) = entity_id.climate_entity_id("climate.main")
  let assert Ok(managed_sensor) =
    entity_id.sensor_entity_id("sensor.managed_temp")
  let assert Ok(unmanaged_sensor) =
    entity_id.sensor_entity_id("sensor.unmanaged_temp")

  let config =
    ha_poller_actor.PollerConfig(
      poll_interval_ms: 5000,
      heating_entity_id: heating_id,
      sleep_button_entity_id: "input_button.goodnight",
      managed_trv_ids: set.new(),
      // Only the managed sensor is in the set
      managed_sensor_ids: set.from_list([managed_sensor]),
    )

  let assert Ok(started) =
    ha_poller_actor.start(
      ha_client: home_assistant.HaClient("http://localhost:8123", "test-token"),
      config: config,
      event_spy: event_spy,
    )

  // Inject mock JSON with both sensors
  let mock_json =
    "[{\"entity_id\":\"sensor.managed_temp\",\"state\":\"20.0\",\"attributes\":{}},{\"entity_id\":\"sensor.unmanaged_temp\",\"state\":\"18.0\",\"attributes\":{}}]"
  process.send(started.data, ha_poller_actor.InjectMockResponse(mock_json))

  // Trigger a poll
  process.send(started.data, ha_poller_actor.PollNow)

  // Collect events
  let events = collect_events(event_spy, 5, 500)

  // Should have SensorUpdated for managed sensor
  let has_managed =
    list.any(events, fn(event) {
      case event {
        ha_poller_actor.SensorUpdated(eid, _) -> eid == managed_sensor
        _ -> False
      }
    })

  // Should NOT have SensorUpdated for unmanaged sensor
  let has_unmanaged =
    list.any(events, fn(event) {
      case event {
        ha_poller_actor.SensorUpdated(eid, _) -> eid == unmanaged_sensor
        _ -> False
      }
    })

  has_managed |> should.be_true
  has_unmanaged |> should.be_false
}

pub fn sensor_update_handles_unavailable_sensor_test() {
  // When a sensor is unavailable, should emit SensorUpdated with None temperature
  let event_spy: process.Subject(ha_poller_actor.PollerEvent) =
    process.new_subject()

  let assert Ok(heating_id) = entity_id.climate_entity_id("climate.main")
  let assert Ok(sensor1) = entity_id.sensor_entity_id("sensor.garage_temp")

  let config =
    ha_poller_actor.PollerConfig(
      poll_interval_ms: 5000,
      heating_entity_id: heating_id,
      sleep_button_entity_id: "input_button.goodnight",
      managed_trv_ids: set.new(),
      managed_sensor_ids: set.from_list([sensor1]),
    )

  let assert Ok(started) =
    ha_poller_actor.start(
      ha_client: home_assistant.HaClient("http://localhost:8123", "test-token"),
      config: config,
      event_spy: event_spy,
    )

  // Inject mock JSON with unavailable sensor
  let mock_json =
    "[{\"entity_id\":\"sensor.garage_temp\",\"state\":\"unavailable\",\"attributes\":{}}]"
  process.send(started.data, ha_poller_actor.InjectMockResponse(mock_json))

  // Trigger a poll
  process.send(started.data, ha_poller_actor.PollNow)

  // Should receive a SensorUpdated event with None temperature
  let events = collect_events(event_spy, 5, 500)

  let has_unavailable_sensor =
    list.any(events, fn(event) {
      case event {
        ha_poller_actor.SensorUpdated(eid, temp) ->
          eid == sensor1 && temp == option.None
        _ -> False
      }
    })

  has_unavailable_sensor |> should.be_true
}

// =============================================================================
// Heating Entity Polling Tests
// =============================================================================

pub fn dispatches_heating_status_changed_for_heating_entity_test() {
  // When polling succeeds and returns the heating entity,
  // should dispatch HeatingStatusChanged event
  let event_spy: process.Subject(ha_poller_actor.PollerEvent) =
    process.new_subject()

  let assert Ok(heating_entity) = entity_id.climate_entity_id("climate.boiler")

  let config =
    ha_poller_actor.PollerConfig(
      poll_interval_ms: 5000,
      heating_entity_id: heating_entity,
      sleep_button_entity_id: "input_button.goodnight",
      managed_trv_ids: set.new(),
      managed_sensor_ids: set.new(),
    )

  let assert Ok(started) =
    ha_poller_actor.start(
      ha_client: home_assistant.HaClient("http://localhost:8123", "test-token"),
      config: config,
      event_spy: event_spy,
    )

  // Inject mock JSON response with heating entity that is heating
  let mock_json =
    "[{\"entity_id\":\"climate.boiler\",\"state\":\"heat\",\"attributes\":{\"current_temperature\":45.0,\"temperature\":50.0,\"hvac_action\":\"heating\"}}]"
  process.send(started.data, ha_poller_actor.InjectMockResponse(mock_json))

  // Trigger a poll
  process.send(started.data, ha_poller_actor.PollNow)

  // Should receive a HeatingStatusChanged event
  let events = collect_events(event_spy, 5, 500)

  // Check we got a HeatingStatusChanged event with is_heating=True
  let has_heating_status =
    list.any(events, fn(event) {
      case event {
        ha_poller_actor.HeatingStatusChanged(is_heating) -> is_heating == True
        _ -> False
      }
    })

  has_heating_status |> should.be_true
}

pub fn heating_status_changed_emits_false_when_not_heating_test() {
  // When heating entity is not actively heating, should emit is_heating=False
  let event_spy: process.Subject(ha_poller_actor.PollerEvent) =
    process.new_subject()

  let assert Ok(heating_entity) = entity_id.climate_entity_id("climate.boiler")

  let config =
    ha_poller_actor.PollerConfig(
      poll_interval_ms: 5000,
      heating_entity_id: heating_entity,
      sleep_button_entity_id: "input_button.goodnight",
      managed_trv_ids: set.new(),
      managed_sensor_ids: set.new(),
    )

  let assert Ok(started) =
    ha_poller_actor.start(
      ha_client: home_assistant.HaClient("http://localhost:8123", "test-token"),
      config: config,
      event_spy: event_spy,
    )

  // Inject mock JSON response with heating entity that is idle
  let mock_json =
    "[{\"entity_id\":\"climate.boiler\",\"state\":\"heat\",\"attributes\":{\"current_temperature\":45.0,\"temperature\":50.0,\"hvac_action\":\"idle\"}}]"
  process.send(started.data, ha_poller_actor.InjectMockResponse(mock_json))

  // Trigger a poll
  process.send(started.data, ha_poller_actor.PollNow)

  // Should receive a HeatingStatusChanged event with is_heating=False
  let events = collect_events(event_spy, 5, 500)

  let has_heating_status_false =
    list.any(events, fn(event) {
      case event {
        ha_poller_actor.HeatingStatusChanged(is_heating) -> is_heating == False
        _ -> False
      }
    })

  has_heating_status_false |> should.be_true
}
