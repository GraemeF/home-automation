import deep_heating/entity_id
import deep_heating/mode
import deep_heating/rooms/room_actor
import deep_heating/scheduling/schedule
import deep_heating/temperature
import deep_heating/timer
import gleam/dict
import gleam/erlang/process.{type Name, type Subject}
import gleam/int
import gleam/option
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

/// Test context containing all the infrastructure needed to test RoomActor
type TestContext {
  TestContext(
    decision_name: Name(room_actor.DecisionMessage),
    decision_spy: Subject(room_actor.DecisionMessage),
    aggregator_spy: Subject(room_actor.AggregatorMessage),
  )
}

/// Create a test context with mock decision actor and aggregator spy
fn make_test_context(test_id: String) -> TestContext {
  let #(decision_name, decision_spy) = make_mock_decision_actor(test_id)
  let aggregator_spy = process.new_subject()
  TestContext(
    decision_name: decision_name,
    decision_spy: decision_spy,
    aggregator_spy: aggregator_spy,
  )
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

// =============================================================================
// Initial State Broadcast Tests
// =============================================================================

pub fn room_actor_broadcasts_initial_state_to_aggregator_on_startup_test() {
  // Bug: dh-33jq.68
  // RoomActor should broadcast its initial state to the StateAggregator
  // immediately after starting, so the UI has state without waiting for
  // the first HA poll.
  let ctx = make_test_context("broadcasts_initial_state")

  let assert Ok(_started) =
    room_actor.start_with_options(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor_name: ctx.decision_name,
      state_aggregator: ctx.aggregator_spy,
      heating_control: option.None,
      get_time: room_actor.get_current_datetime,
      timer_interval_ms: 0,
      initial_adjustment: 0.0,
      send_after: timer.spy_send_after(process.new_subject()),
    )

  // StateAggregator should receive initial state immediately after startup
  let assert Ok(msg) = process.receive(ctx.aggregator_spy, 500)
  case msg {
    room_actor.RoomUpdated(name, state) -> {
      name |> should.equal("lounge")
      state.name |> should.equal("lounge")
    }
  }
}

pub fn room_actor_broadcasts_initial_state_to_decision_actor_on_startup_test() {
  // RoomDecisionActor should also receive initial state on startup
  let ctx = make_test_context("broadcasts_initial_state_decision")

  let assert Ok(_started) =
    room_actor.start_with_options(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor_name: ctx.decision_name,
      state_aggregator: ctx.aggregator_spy,
      heating_control: option.None,
      get_time: room_actor.get_current_datetime,
      timer_interval_ms: 0,
      initial_adjustment: 0.0,
      send_after: timer.spy_send_after(process.new_subject()),
    )

  // RoomDecisionActor should receive initial state immediately after startup
  let assert Ok(msg) = process.receive(ctx.decision_spy, 500)
  case msg {
    room_actor.RoomStateChanged(state) -> {
      state.name |> should.equal("lounge")
    }
  }
}

pub fn room_actor_broadcasts_initial_state_to_heating_control_on_startup_test() {
  // HeatingControlActor should also receive initial state on startup
  let ctx = make_test_context("broadcasts_initial_state_heating")
  let heating_control_spy: Subject(room_actor.HeatingControlMessage) =
    process.new_subject()

  let assert Ok(_started) =
    room_actor.start_with_options(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor_name: ctx.decision_name,
      state_aggregator: ctx.aggregator_spy,
      heating_control: option.Some(heating_control_spy),
      get_time: room_actor.get_current_datetime,
      timer_interval_ms: 0,
      initial_adjustment: 0.0,
      send_after: timer.spy_send_after(process.new_subject()),
    )

  // HeatingControlActor should receive initial state immediately after startup
  let assert Ok(msg) = process.receive(heating_control_spy, 500)
  case msg {
    room_actor.HeatingRoomUpdated(name, state) -> {
      name |> should.equal("lounge")
      state.name |> should.equal("lounge")
    }
  }
}

// =============================================================================
// Actor Startup Tests
// =============================================================================

pub fn room_actor_starts_successfully_test() {
  // Create dependencies
  let #(decision_name, _spy) = make_mock_decision_actor("starts_successfully")
  let state_aggregator = process.new_subject()

  // Room actor should start successfully
  let result =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor_name: decision_name,
      state_aggregator: state_aggregator,
      heating_control: option.None,
    )
  should.be_ok(result)
}

pub fn room_actor_is_alive_after_start_test() {
  let #(decision_name, _spy) = make_mock_decision_actor("is_alive")
  let state_aggregator = process.new_subject()

  let assert Ok(started) =
    room_actor.start(
      name: "bedroom",
      schedule: make_test_schedule(),
      decision_actor_name: decision_name,
      state_aggregator: state_aggregator,
      heating_control: option.None,
    )

  // The actor should be running
  process.is_alive(started.pid) |> should.be_true
}

// =============================================================================
// GetState Tests
// =============================================================================

pub fn room_actor_returns_initial_state_test() {
  let ctx = make_test_context("initial_state")

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor_name: ctx.decision_name,
      state_aggregator: ctx.aggregator_spy,
      heating_control: option.None,
    )

  // Query state
  let reply_subject = process.new_subject()
  process.send(started.data, room_actor.GetState(reply_subject))

  let assert Ok(state) = process.receive(reply_subject, 1000)

  // Verify initial state
  state.name |> should.equal("lounge")
  state.house_mode |> should.equal(mode.HouseModeAuto)
  state.adjustment |> should.equal(0.0)
}

pub fn room_actor_starts_with_initial_adjustment_test() {
  let ctx = make_test_context("with_adjustment")

  let assert Ok(started) =
    room_actor.start_with_adjustment(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor_name: ctx.decision_name,
      state_aggregator: ctx.aggregator_spy,
      heating_control: option.None,
      initial_adjustment: 1.5,
    )

  // Query state
  let reply_subject = process.new_subject()
  process.send(started.data, room_actor.GetState(reply_subject))

  let assert Ok(state) = process.receive(reply_subject, 1000)

  // Verify initial adjustment is set
  state.adjustment |> should.equal(1.5)
}

pub fn room_actor_applies_initial_adjustment_to_target_test() {
  let ctx = make_test_context("adjustment_to_target")

  // Schedule has 20°C, adjustment of +2.0 should result in 22°C target
  let assert Ok(started) =
    room_actor.start_with_adjustment(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor_name: ctx.decision_name,
      state_aggregator: ctx.aggregator_spy,
      heating_control: option.None,
      initial_adjustment: 2.0,
    )

  let reply_subject = process.new_subject()
  process.send(started.data, room_actor.GetState(reply_subject))

  let assert Ok(state) = process.receive(reply_subject, 1000)

  // Target should be schedule (20°C) + adjustment (2°C) = 22°C
  state.target_temperature
  |> should.equal(option.Some(temperature.temperature(22.0)))
}

pub fn room_actor_clamps_initial_adjustment_test() {
  let ctx = make_test_context("clamps_adjustment")

  // Initial adjustment exceeds max (3.0), should be clamped
  let assert Ok(started) =
    room_actor.start_with_adjustment(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor_name: ctx.decision_name,
      state_aggregator: ctx.aggregator_spy,
      heating_control: option.None,
      initial_adjustment: 5.0,
    )

  let reply_subject = process.new_subject()
  process.send(started.data, room_actor.GetState(reply_subject))

  let assert Ok(state) = process.receive(reply_subject, 1000)

  // Should be clamped to max adjustment (3.0)
  state.adjustment |> should.equal(3.0)
}

// =============================================================================
// TRV State Aggregation Tests
// =============================================================================

pub fn room_actor_tracks_trv_temperature_test() {
  let ctx = make_test_context("tracks_trv_temp")

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor_name: ctx.decision_name,
      state_aggregator: ctx.aggregator_spy,
      heating_control: option.None,
    )

  // Create a TRV entity ID
  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  // Send TRV temperature update
  let temp = temperature.temperature(21.5)
  process.send(started.data, room_actor.TrvTemperatureChanged(trv_id, temp))

  // Give actor time to process
  process.sleep(10)

  // Query state
  let reply_subject = process.new_subject()
  process.send(started.data, room_actor.GetState(reply_subject))
  let assert Ok(state) = process.receive(reply_subject, 1000)

  // Verify TRV state is tracked
  let trv_states = state.trv_states
  dict.size(trv_states) |> should.equal(1)

  let assert Ok(trv_state) = dict.get(trv_states, trv_id)
  trv_state.temperature |> should.equal(option.Some(temp))
}

pub fn room_actor_tracks_trv_target_test() {
  let ctx = make_test_context("tracks_trv_target")

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor_name: ctx.decision_name,
      state_aggregator: ctx.aggregator_spy,
      heating_control: option.None,
    )

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  // Send TRV target update
  let target = temperature.temperature(22.0)
  process.send(started.data, room_actor.TrvTargetChanged(trv_id, target))

  process.sleep(10)

  let reply_subject = process.new_subject()
  process.send(started.data, room_actor.GetState(reply_subject))
  let assert Ok(state) = process.receive(reply_subject, 1000)

  let assert Ok(trv_state) = dict.get(state.trv_states, trv_id)
  trv_state.target |> should.equal(option.Some(target))
}

pub fn room_actor_aggregates_multiple_trvs_test() {
  let ctx = make_test_context("aggregates_multiple_trvs")

  let assert Ok(started) =
    room_actor.start(
      name: "bedroom",
      schedule: make_test_schedule(),
      decision_actor_name: ctx.decision_name,
      state_aggregator: ctx.aggregator_spy,
      heating_control: option.None,
    )

  let assert Ok(trv1) = entity_id.climate_entity_id("climate.bedroom_trv_1")
  let assert Ok(trv2) = entity_id.climate_entity_id("climate.bedroom_trv_2")

  // Send updates from two different TRVs
  let temp1 = temperature.temperature(20.0)
  let temp2 = temperature.temperature(21.0)
  process.send(started.data, room_actor.TrvTemperatureChanged(trv1, temp1))
  process.send(started.data, room_actor.TrvTemperatureChanged(trv2, temp2))

  process.sleep(10)

  let reply_subject = process.new_subject()
  process.send(started.data, room_actor.GetState(reply_subject))
  let assert Ok(state) = process.receive(reply_subject, 1000)

  // Both TRVs should be tracked
  dict.size(state.trv_states) |> should.equal(2)

  let assert Ok(s1) = dict.get(state.trv_states, trv1)
  let assert Ok(s2) = dict.get(state.trv_states, trv2)
  s1.temperature |> should.equal(option.Some(temp1))
  s2.temperature |> should.equal(option.Some(temp2))
}

pub fn room_actor_notifies_decision_actor_on_trv_change_test() {
  let ctx = make_test_context("notifies_decision_on_trv_change")

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor_name: ctx.decision_name,
      state_aggregator: ctx.aggregator_spy,
      heating_control: option.None,
    )

  // Consume initial state broadcast
  let assert Ok(_initial) = process.receive(ctx.decision_spy, 1000)

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  // Send TRV temperature update
  let temp = temperature.temperature(21.5)
  process.send(started.data, room_actor.TrvTemperatureChanged(trv_id, temp))

  // Decision actor should receive notification
  let assert Ok(msg) = process.receive(ctx.decision_spy, 1000)
  case msg {
    room_actor.RoomStateChanged(state) -> {
      state.name |> should.equal("lounge")
    }
  }
}

// =============================================================================
// House Mode Tests
// =============================================================================

pub fn room_actor_handles_house_mode_change_test() {
  let ctx = make_test_context("handles_house_mode_change")

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor_name: ctx.decision_name,
      state_aggregator: ctx.aggregator_spy,
      heating_control: option.None,
    )

  // Send house mode change to Sleeping
  process.send(
    started.data,
    room_actor.HouseModeChanged(mode.HouseModeSleeping),
  )

  process.sleep(10)

  // Query state
  let reply_subject = process.new_subject()
  process.send(started.data, room_actor.GetState(reply_subject))
  let assert Ok(state) = process.receive(reply_subject, 1000)

  // Verify house mode was updated
  state.house_mode |> should.equal(mode.HouseModeSleeping)
}

pub fn room_actor_notifies_decision_actor_on_house_mode_change_test() {
  let ctx = make_test_context("notifies_decision_on_house_mode")

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor_name: ctx.decision_name,
      state_aggregator: ctx.aggregator_spy,
      heating_control: option.None,
    )

  // Consume initial state broadcast
  let assert Ok(_initial) = process.receive(ctx.decision_spy, 1000)

  // Send house mode change
  process.send(
    started.data,
    room_actor.HouseModeChanged(mode.HouseModeSleeping),
  )

  // Decision actor should receive notification
  let assert Ok(msg) = process.receive(ctx.decision_spy, 1000)
  case msg {
    room_actor.RoomStateChanged(state) -> {
      state.house_mode |> should.equal(mode.HouseModeSleeping)
    }
  }
}

// =============================================================================
// Adjustment Tests
// =============================================================================

pub fn room_actor_handles_adjustment_change_test() {
  let ctx = make_test_context("handles_adjustment_change")

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor_name: ctx.decision_name,
      state_aggregator: ctx.aggregator_spy,
      heating_control: option.None,
    )

  // Send adjustment change
  process.send(started.data, room_actor.AdjustmentChanged(2.0))

  process.sleep(10)

  let reply_subject = process.new_subject()
  process.send(started.data, room_actor.GetState(reply_subject))
  let assert Ok(state) = process.receive(reply_subject, 1000)

  state.adjustment |> should.equal(2.0)
}

pub fn room_actor_clamps_adjustment_to_max_test() {
  let ctx = make_test_context("clamps_adjustment_max")

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor_name: ctx.decision_name,
      state_aggregator: ctx.aggregator_spy,
      heating_control: option.None,
    )

  // Try to set adjustment above max (3.0)
  process.send(started.data, room_actor.AdjustmentChanged(5.0))

  process.sleep(10)

  let reply_subject = process.new_subject()
  process.send(started.data, room_actor.GetState(reply_subject))
  let assert Ok(state) = process.receive(reply_subject, 1000)

  // Should be clamped to 3.0
  state.adjustment |> should.equal(3.0)
}

pub fn room_actor_clamps_adjustment_to_min_test() {
  let ctx = make_test_context("clamps_adjustment_min")

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor_name: ctx.decision_name,
      state_aggregator: ctx.aggregator_spy,
      heating_control: option.None,
    )

  // Try to set adjustment below min (-3.0)
  process.send(started.data, room_actor.AdjustmentChanged(-5.0))

  process.sleep(10)

  let reply_subject = process.new_subject()
  process.send(started.data, room_actor.GetState(reply_subject))
  let assert Ok(state) = process.receive(reply_subject, 1000)

  // Should be clamped to -3.0
  state.adjustment |> should.equal(-3.0)
}

// =============================================================================
// External Temperature Tests
// =============================================================================

pub fn room_actor_tracks_external_temperature_test() {
  let ctx = make_test_context("tracks_external_temp")

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor_name: ctx.decision_name,
      state_aggregator: ctx.aggregator_spy,
      heating_control: option.None,
    )

  // Send external temperature update
  let temp = temperature.temperature(19.5)
  process.send(started.data, room_actor.ExternalTempChanged(temp))

  process.sleep(10)

  let reply_subject = process.new_subject()
  process.send(started.data, room_actor.GetState(reply_subject))
  let assert Ok(state) = process.receive(reply_subject, 1000)

  state.temperature |> should.equal(option.Some(temp))
}

// =============================================================================
// TRV Mode Change Tests
// =============================================================================

pub fn room_actor_tracks_trv_mode_test() {
  let ctx = make_test_context("tracks_trv_mode")

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor_name: ctx.decision_name,
      state_aggregator: ctx.aggregator_spy,
      heating_control: option.None,
    )

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  // Send TRV mode update
  process.send(started.data, room_actor.TrvModeChanged(trv_id, mode.HvacHeat))

  process.sleep(10)

  let reply_subject = process.new_subject()
  process.send(started.data, room_actor.GetState(reply_subject))
  let assert Ok(state) = process.receive(reply_subject, 1000)

  let assert Ok(trv_state) = dict.get(state.trv_states, trv_id)
  trv_state.mode |> should.equal(mode.HvacHeat)
}

pub fn room_actor_notifies_decision_actor_on_trv_mode_change_test() {
  let ctx = make_test_context("notifies_on_trv_mode")

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor_name: ctx.decision_name,
      state_aggregator: ctx.aggregator_spy,
      heating_control: option.None,
    )

  // Consume initial state broadcast
  let assert Ok(_initial) = process.receive(ctx.decision_spy, 1000)

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  // Send TRV mode update
  process.send(started.data, room_actor.TrvModeChanged(trv_id, mode.HvacHeat))

  // Decision actor should receive notification
  let assert Ok(msg) = process.receive(ctx.decision_spy, 1000)
  case msg {
    room_actor.RoomStateChanged(state) -> {
      state.name |> should.equal("lounge")
    }
  }
}

// =============================================================================
// TRV Is Heating Change Tests
// =============================================================================

pub fn room_actor_tracks_trv_is_heating_test() {
  let ctx = make_test_context("tracks_trv_is_heating")

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor_name: ctx.decision_name,
      state_aggregator: ctx.aggregator_spy,
      heating_control: option.None,
    )

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  // Send TRV is_heating update
  process.send(started.data, room_actor.TrvIsHeatingChanged(trv_id, True))

  process.sleep(10)

  let reply_subject = process.new_subject()
  process.send(started.data, room_actor.GetState(reply_subject))
  let assert Ok(state) = process.receive(reply_subject, 1000)

  let assert Ok(trv_state) = dict.get(state.trv_states, trv_id)
  trv_state.is_heating |> should.be_true
}

pub fn room_actor_notifies_decision_actor_on_trv_is_heating_change_test() {
  let ctx = make_test_context("notifies_on_trv_is_heating")

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor_name: ctx.decision_name,
      state_aggregator: ctx.aggregator_spy,
      heating_control: option.None,
    )

  // Consume initial state broadcast
  let assert Ok(_initial) = process.receive(ctx.decision_spy, 1000)

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  // Send TRV is_heating update
  process.send(started.data, room_actor.TrvIsHeatingChanged(trv_id, True))

  // Decision actor should receive notification
  let assert Ok(msg) = process.receive(ctx.decision_spy, 1000)
  case msg {
    room_actor.RoomStateChanged(state) -> {
      state.name |> should.equal("lounge")
    }
  }
}

// =============================================================================
// Target Temperature Calculation Tests
// =============================================================================

pub fn compute_target_temp_returns_scheduled_in_auto_mode_test() {
  // Schedule: 20°C all day
  let schedule = make_test_schedule()
  let assert Ok(time) = schedule.time_of_day(10, 0)

  // In Auto mode with no adjustment, should return scheduled temp (20°C)
  let result =
    room_actor.compute_target_temperature(
      schedule: schedule,
      house_mode: mode.HouseModeAuto,
      adjustment: 0.0,
      day: schedule.Monday,
      time: time,
    )

  result |> should.equal(option.Some(temperature.temperature(20.0)))
}

pub fn compute_target_temp_applies_positive_adjustment_test() {
  let schedule = make_test_schedule()
  let assert Ok(time) = schedule.time_of_day(10, 0)

  // With +2°C adjustment, should return 22°C
  let result =
    room_actor.compute_target_temperature(
      schedule: schedule,
      house_mode: mode.HouseModeAuto,
      adjustment: 2.0,
      day: schedule.Monday,
      time: time,
    )

  result |> should.equal(option.Some(temperature.temperature(22.0)))
}

pub fn compute_target_temp_applies_negative_adjustment_test() {
  let schedule = make_test_schedule()
  let assert Ok(time) = schedule.time_of_day(10, 0)

  // With -2°C adjustment, should return 18°C
  let result =
    room_actor.compute_target_temperature(
      schedule: schedule,
      house_mode: mode.HouseModeAuto,
      adjustment: -2.0,
      day: schedule.Monday,
      time: time,
    )

  result |> should.equal(option.Some(temperature.temperature(18.0)))
}

pub fn compute_target_temp_clamps_to_min_room_target_test() {
  // Schedule with low temp (10°C)
  let assert Ok(time) = schedule.time_of_day(0, 0)
  let entry =
    schedule.ScheduleEntry(
      start: time,
      target_temperature: temperature.temperature(10.0),
    )
  let day = [entry]
  let low_schedule =
    schedule.WeekSchedule(
      monday: day,
      tuesday: day,
      wednesday: day,
      thursday: day,
      friday: day,
      saturday: day,
      sunday: day,
    )

  // Even with 10°C scheduled, should clamp to min (16°C)
  let result =
    room_actor.compute_target_temperature(
      schedule: low_schedule,
      house_mode: mode.HouseModeAuto,
      adjustment: 0.0,
      day: schedule.Monday,
      time: time,
    )

  result |> should.equal(option.Some(temperature.min_room_target))
}

pub fn compute_target_temp_clamps_to_max_trv_target_test() {
  // Schedule with high temp (40°C)
  let assert Ok(time) = schedule.time_of_day(0, 0)
  let entry =
    schedule.ScheduleEntry(
      start: time,
      target_temperature: temperature.temperature(40.0),
    )
  let day = [entry]
  let high_schedule =
    schedule.WeekSchedule(
      monday: day,
      tuesday: day,
      wednesday: day,
      thursday: day,
      friday: day,
      saturday: day,
      sunday: day,
    )

  // Even with 40°C scheduled, should clamp to max (32°C)
  let result =
    room_actor.compute_target_temperature(
      schedule: high_schedule,
      house_mode: mode.HouseModeAuto,
      adjustment: 0.0,
      day: schedule.Monday,
      time: time,
    )

  result |> should.equal(option.Some(temperature.max_trv_command_target))
}

pub fn compute_target_temp_returns_min_in_sleeping_mode_test() {
  let schedule = make_test_schedule()
  let assert Ok(time) = schedule.time_of_day(10, 0)

  // In Sleeping mode, should always return min room target (16°C)
  // regardless of schedule or adjustment
  let result =
    room_actor.compute_target_temperature(
      schedule: schedule,
      house_mode: mode.HouseModeSleeping,
      adjustment: 3.0,
      day: schedule.Monday,
      time: time,
    )

  result |> should.equal(option.Some(temperature.min_room_target))
}

// =============================================================================
// Actor Integration Tests - Target Temperature Computed
// =============================================================================

pub fn room_actor_computes_target_on_startup_test() {
  let ctx = make_test_context("computes_target_startup")

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor_name: ctx.decision_name,
      state_aggregator: ctx.aggregator_spy,
      heating_control: option.None,
    )

  // Query state
  let reply_subject = process.new_subject()
  process.send(started.data, room_actor.GetState(reply_subject))
  let assert Ok(state) = process.receive(reply_subject, 1000)

  // Target temperature should be computed (not None)
  state.target_temperature |> option.is_some |> should.be_true
}

pub fn room_actor_recomputes_target_on_house_mode_change_test() {
  let ctx = make_test_context("recomputes_target_house_mode")

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor_name: ctx.decision_name,
      state_aggregator: ctx.aggregator_spy,
      heating_control: option.None,
    )

  // Get initial state (should be Auto mode)
  let reply1 = process.new_subject()
  process.send(started.data, room_actor.GetState(reply1))
  let assert Ok(initial_state) = process.receive(reply1, 1000)
  let assert option.Some(initial_target) = initial_state.target_temperature

  // Change to Sleeping mode
  process.send(
    started.data,
    room_actor.HouseModeChanged(mode.HouseModeSleeping),
  )
  process.sleep(10)

  // Get new state
  let reply2 = process.new_subject()
  process.send(started.data, room_actor.GetState(reply2))
  let assert Ok(sleeping_state) = process.receive(reply2, 1000)

  // Target should be min_room_target (16°C) in Sleeping mode
  sleeping_state.target_temperature
  |> should.equal(option.Some(temperature.min_room_target))

  // And should be different from initial if schedule was > 16°C
  // (our test schedule is 20°C)
  case temperature.eq(initial_target, temperature.min_room_target) {
    True -> Nil
    False ->
      sleeping_state.target_temperature
      |> should.not_equal(option.Some(initial_target))
  }
}

pub fn room_actor_recomputes_target_on_adjustment_change_test() {
  let ctx = make_test_context("recomputes_target_adjustment")

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor_name: ctx.decision_name,
      state_aggregator: ctx.aggregator_spy,
      heating_control: option.None,
    )

  // Get initial state
  let reply1 = process.new_subject()
  process.send(started.data, room_actor.GetState(reply1))
  let assert Ok(initial_state) = process.receive(reply1, 1000)
  let assert option.Some(initial_target) = initial_state.target_temperature

  // Apply +2°C adjustment
  process.send(started.data, room_actor.AdjustmentChanged(2.0))
  process.sleep(10)

  // Get new state
  let reply2 = process.new_subject()
  process.send(started.data, room_actor.GetState(reply2))
  let assert Ok(adjusted_state) = process.receive(reply2, 1000)

  // Target should be 2°C higher than initial (20°C + 2°C = 22°C)
  let expected = temperature.add(initial_target, temperature.temperature(2.0))
  adjusted_state.target_temperature |> should.equal(option.Some(expected))
}

// =============================================================================
// StateAggregator Notification Tests
// =============================================================================

pub fn room_actor_notifies_state_aggregator_on_trv_change_test() {
  let ctx = make_test_context("notifies_state_aggregator")

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor_name: ctx.decision_name,
      state_aggregator: ctx.aggregator_spy,
      heating_control: option.None,
    )

  // Consume initial state broadcast
  let assert Ok(_initial) = process.receive(ctx.aggregator_spy, 1000)

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  // Send TRV temperature update
  let temp = temperature.temperature(21.5)
  process.send(started.data, room_actor.TrvTemperatureChanged(trv_id, temp))

  // State aggregator should receive notification
  let assert Ok(msg) = process.receive(ctx.aggregator_spy, 1000)
  case msg {
    room_actor.RoomUpdated(name, state) -> {
      name |> should.equal("lounge")
      state.name |> should.equal("lounge")
    }
  }
}

// =============================================================================
// Room Mode Derivation Tests
// =============================================================================

pub fn room_actor_initial_room_mode_is_auto_test() {
  // When house_mode is Auto and no TRVs, room_mode should be Auto
  let ctx = make_test_context("initial_room_mode_auto")

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor_name: ctx.decision_name,
      state_aggregator: ctx.aggregator_spy,
      heating_control: option.None,
    )

  let reply_subject = process.new_subject()
  process.send(started.data, room_actor.GetState(reply_subject))
  let assert Ok(state) = process.receive(reply_subject, 1000)

  state.room_mode |> should.equal(mode.RoomModeAuto)
}

pub fn room_actor_room_mode_is_off_when_any_trv_off_test() {
  // If any TRV has HvacOff mode, room_mode should be RoomModeOff
  let ctx = make_test_context("room_mode_off_trv_off")

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor_name: ctx.decision_name,
      state_aggregator: ctx.aggregator_spy,
      heating_control: option.None,
    )

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  // Set TRV mode to Off
  process.send(started.data, room_actor.TrvModeChanged(trv_id, mode.HvacOff))
  process.sleep(10)

  let reply_subject = process.new_subject()
  process.send(started.data, room_actor.GetState(reply_subject))
  let assert Ok(state) = process.receive(reply_subject, 1000)

  state.room_mode |> should.equal(mode.RoomModeOff)
}

pub fn room_actor_room_mode_is_auto_when_all_trvs_heat_test() {
  // If all TRVs are in heat mode and house_mode is Auto, room_mode is Auto
  let ctx = make_test_context("room_mode_auto_all_heat")

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor_name: ctx.decision_name,
      state_aggregator: ctx.aggregator_spy,
      heating_control: option.None,
    )

  let assert Ok(trv1) = entity_id.climate_entity_id("climate.lounge_trv_1")
  let assert Ok(trv2) = entity_id.climate_entity_id("climate.lounge_trv_2")

  // Set both TRVs to Heat mode
  process.send(started.data, room_actor.TrvModeChanged(trv1, mode.HvacHeat))
  process.send(started.data, room_actor.TrvModeChanged(trv2, mode.HvacHeat))
  process.sleep(10)

  let reply_subject = process.new_subject()
  process.send(started.data, room_actor.GetState(reply_subject))
  let assert Ok(state) = process.receive(reply_subject, 1000)

  state.room_mode |> should.equal(mode.RoomModeAuto)
}

pub fn room_actor_room_mode_is_off_when_one_of_many_trvs_off_test() {
  // If even one TRV is off, room_mode should be Off
  let ctx = make_test_context("room_mode_off_one_trv_off")

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor_name: ctx.decision_name,
      state_aggregator: ctx.aggregator_spy,
      heating_control: option.None,
    )

  let assert Ok(trv1) = entity_id.climate_entity_id("climate.lounge_trv_1")
  let assert Ok(trv2) = entity_id.climate_entity_id("climate.lounge_trv_2")

  // One TRV is Heat, one is Off
  process.send(started.data, room_actor.TrvModeChanged(trv1, mode.HvacHeat))
  process.send(started.data, room_actor.TrvModeChanged(trv2, mode.HvacOff))
  process.sleep(10)

  let reply_subject = process.new_subject()
  process.send(started.data, room_actor.GetState(reply_subject))
  let assert Ok(state) = process.receive(reply_subject, 1000)

  state.room_mode |> should.equal(mode.RoomModeOff)
}

pub fn room_actor_room_mode_is_sleeping_when_house_sleeping_test() {
  // If house_mode is Sleeping and no TRV is off, room_mode is Sleeping
  let ctx = make_test_context("room_mode_sleeping")

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor_name: ctx.decision_name,
      state_aggregator: ctx.aggregator_spy,
      heating_control: option.None,
    )

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  // Set TRV to Heat mode
  process.send(started.data, room_actor.TrvModeChanged(trv_id, mode.HvacHeat))
  // Set house mode to Sleeping
  process.send(
    started.data,
    room_actor.HouseModeChanged(mode.HouseModeSleeping),
  )
  process.sleep(10)

  let reply_subject = process.new_subject()
  process.send(started.data, room_actor.GetState(reply_subject))
  let assert Ok(state) = process.receive(reply_subject, 1000)

  state.room_mode |> should.equal(mode.RoomModeSleeping)
}

pub fn room_actor_room_mode_off_overrides_sleeping_test() {
  // TRV off should override house sleeping mode
  let ctx = make_test_context("room_mode_off_overrides_sleeping")

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor_name: ctx.decision_name,
      state_aggregator: ctx.aggregator_spy,
      heating_control: option.None,
    )

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  // Set house mode to Sleeping
  process.send(
    started.data,
    room_actor.HouseModeChanged(mode.HouseModeSleeping),
  )
  // Set TRV to Off mode
  process.send(started.data, room_actor.TrvModeChanged(trv_id, mode.HvacOff))
  process.sleep(10)

  let reply_subject = process.new_subject()
  process.send(started.data, room_actor.GetState(reply_subject))
  let assert Ok(state) = process.receive(reply_subject, 1000)

  // Off overrides Sleeping
  state.room_mode |> should.equal(mode.RoomModeOff)
}

// =============================================================================
// Timer-Based Schedule Refresh Tests
// =============================================================================

fn make_schedule_with_morning_change() -> schedule.WeekSchedule {
  // Schedule: 18°C at midnight, 21°C at 09:00
  let assert Ok(midnight) = schedule.time_of_day(0, 0)
  let assert Ok(morning) = schedule.time_of_day(9, 0)
  let entries = [
    schedule.ScheduleEntry(
      start: midnight,
      target_temperature: temperature.temperature(18.0),
    ),
    schedule.ScheduleEntry(
      start: morning,
      target_temperature: temperature.temperature(21.0),
    ),
  ]
  schedule.WeekSchedule(
    monday: entries,
    tuesday: entries,
    wednesday: entries,
    thursday: entries,
    friday: entries,
    saturday: entries,
    sunday: entries,
  )
}

pub fn timer_triggers_target_recomputation_test() {
  // The actor should automatically recompute target temperature every timer interval.
  // This allows schedule changes to take effect without external triggers.
  //
  // Scenario (with ramping algorithm):
  // 1. Start with time 06:00 (3 hours before 09:00→21°C)
  //    - Active entry 00:00→18°C: effective = 18°C
  //    - Future entry 09:00→21°C, 3 hours away: effective = 21 - 1.5 = 19.5°C
  //    - max(18, 19.5) = 19.5°C
  // 2. After timer fires with time 09:01, target should update to 21°C
  //    - Active entry 09:00→21°C: effective = 21°C

  // Use an atomic counter to track call count across process boundaries
  let counter = create_counter()

  let get_time = fn() {
    let count = increment_counter(counter)
    case count {
      // First call (init) - return 06:00 (3 hours before schedule change)
      1 -> {
        let assert Ok(time) = schedule.time_of_day(6, 0)
        #(schedule.Monday, time)
      }
      // Subsequent calls - return 09:01 (after schedule change)
      _ -> {
        let assert Ok(time) = schedule.time_of_day(9, 1)
        #(schedule.Monday, time)
      }
    }
  }

  let ctx = make_test_context("timer_recomputation")

  // Start actor with short timer interval (100ms for testing)
  let assert Ok(started) =
    room_actor.start_with_timer_interval(
      name: "lounge",
      schedule: make_schedule_with_morning_change(),
      decision_actor_name: ctx.decision_name,
      state_aggregator: ctx.aggregator_spy,
      heating_control: option.None,
      get_time: get_time,
      timer_interval_ms: 100,
      initial_adjustment: 0.0,
    )

  // Check initial state - should be 19.5°C (time is 06:00, ramping towards 09:00)
  let reply = process.new_subject()
  process.send(started.data, room_actor.GetState(reply))
  let assert Ok(initial_state) = process.receive(reply, 1000)
  initial_state.target_temperature
  |> should.equal(option.Some(temperature.temperature(19.5)))

  // Wait for timer to fire (>100ms)
  process.sleep(150)

  // Now target should be 21°C (time is 09:01 on timer re-evaluation)
  let reply2 = process.new_subject()
  process.send(started.data, room_actor.GetState(reply2))
  let assert Ok(updated_state) = process.receive(reply2, 1000)
  updated_state.target_temperature
  |> should.equal(option.Some(temperature.temperature(21.0)))

  // Clean up
  delete_counter(counter)
}

// =============================================================================
// Injectable Timer Tests (spy_send_after)
// =============================================================================

pub fn room_actor_schedules_timer_on_startup_test() {
  // Verify that the actor schedules a timer on startup with the correct interval.
  // Uses spy_send_after to capture timer requests without actually scheduling.

  let timer_spy: Subject(timer.TimerRequest(room_actor.Message)) =
    process.new_subject()
  let ctx = make_test_context("schedules_timer")

  let assert Ok(_started) =
    room_actor.start_with_options(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor_name: ctx.decision_name,
      state_aggregator: ctx.aggregator_spy,
      heating_control: option.None,
      get_time: room_actor.get_current_datetime,
      timer_interval_ms: 60_000,
      initial_adjustment: 0.0,
      send_after: timer.spy_send_after(timer_spy),
    )

  // Timer spy should receive a timer request
  let assert Ok(timer_request) = process.receive(timer_spy, 1000)

  // Verify the timer was scheduled with correct interval
  timer_request.delay_ms |> should.equal(60_000)

  // Verify the message is ReComputeTarget
  case timer_request.msg {
    room_actor.ReComputeTarget -> should.be_ok(Ok(Nil))
    _ -> should.fail()
  }
}

pub fn room_actor_no_timer_when_interval_zero_test() {
  // Verify that no timer is scheduled when timer_interval_ms is 0.

  let timer_spy: Subject(timer.TimerRequest(room_actor.Message)) =
    process.new_subject()
  let ctx = make_test_context("no_timer")

  let assert Ok(_started) =
    room_actor.start_with_options(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor_name: ctx.decision_name,
      state_aggregator: ctx.aggregator_spy,
      heating_control: option.None,
      get_time: room_actor.get_current_datetime,
      timer_interval_ms: 0,
      initial_adjustment: 0.0,
      send_after: timer.spy_send_after(timer_spy),
    )

  // Timer spy should NOT receive any timer request
  let result = process.receive(timer_spy, 100)
  result |> should.be_error
}

pub fn room_actor_reschedules_timer_after_firing_test() {
  // Verify that the timer is rescheduled after ReComputeTarget fires.
  // Uses instant_send_after so the initial timer fires immediately,
  // then spy_send_after for subsequent timers wouldn't work directly.
  // Instead, we manually send ReComputeTarget and check the spy.

  let timer_spy: Subject(timer.TimerRequest(room_actor.Message)) =
    process.new_subject()
  let ctx = make_test_context("reschedules_timer")

  // Start with spy timer (timer_interval_ms > 0)
  let assert Ok(started) =
    room_actor.start_with_options(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor_name: ctx.decision_name,
      state_aggregator: ctx.aggregator_spy,
      heating_control: option.None,
      get_time: room_actor.get_current_datetime,
      timer_interval_ms: 60_000,
      initial_adjustment: 0.0,
      send_after: timer.spy_send_after(timer_spy),
    )

  // Consume the initial timer request from startup
  let assert Ok(_initial_request) = process.receive(timer_spy, 1000)

  // Manually send ReComputeTarget to trigger reschedule
  process.send(started.data, room_actor.ReComputeTarget)

  // The actor should schedule a new timer
  let assert Ok(reschedule_request) = process.receive(timer_spy, 1000)

  // Verify the rescheduled timer has correct interval
  reschedule_request.delay_ms |> should.equal(60_000)

  // Verify the message is ReComputeTarget
  case reschedule_request.msg {
    room_actor.ReComputeTarget -> should.be_ok(Ok(Nil))
    _ -> should.fail()
  }
}

// =============================================================================
// Atomics Counter Helpers for Cross-Process State
// =============================================================================

/// Opaque type for atomic counter reference
type AtomicCounter

/// Create an atomic counter, returns counter reference
@external(erlang, "room_actor_test_ffi", "create_counter")
fn create_counter() -> AtomicCounter

/// Atomically increment counter and return new value
@external(erlang, "room_actor_test_ffi", "increment_counter")
fn increment_counter(counter: AtomicCounter) -> Int

/// Delete counter (no-op for atomics, they're garbage collected)
@external(erlang, "room_actor_test_ffi", "delete_counter")
fn delete_counter(counter: AtomicCounter) -> Nil
