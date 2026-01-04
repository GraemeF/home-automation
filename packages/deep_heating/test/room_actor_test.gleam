import deep_heating/actor/room_actor
import deep_heating/entity_id
import deep_heating/mode
import deep_heating/schedule
import deep_heating/temperature
import gleam/dict
import gleam/erlang/process
import gleam/option
import gleeunit/should

// =============================================================================
// Test Helpers
// =============================================================================

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
// Actor Startup Tests
// =============================================================================

pub fn room_actor_starts_successfully_test() {
  // Create dependencies
  let decision_actor = process.new_subject()
  let state_aggregator = process.new_subject()

  // Room actor should start successfully
  let result =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor: decision_actor,
      state_aggregator: state_aggregator,
    )
  should.be_ok(result)
}

pub fn room_actor_is_alive_after_start_test() {
  let decision_actor = process.new_subject()
  let state_aggregator = process.new_subject()

  let assert Ok(started) =
    room_actor.start(
      name: "bedroom",
      schedule: make_test_schedule(),
      decision_actor: decision_actor,
      state_aggregator: state_aggregator,
    )

  // The actor should be running
  process.is_alive(started.pid) |> should.be_true
}

// =============================================================================
// GetState Tests
// =============================================================================

pub fn room_actor_returns_initial_state_test() {
  let decision_actor = process.new_subject()
  let state_aggregator = process.new_subject()

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor: decision_actor,
      state_aggregator: state_aggregator,
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

// =============================================================================
// TRV State Aggregation Tests
// =============================================================================

pub fn room_actor_tracks_trv_temperature_test() {
  let decision_actor: process.Subject(room_actor.DecisionMessage) =
    process.new_subject()
  let state_aggregator = process.new_subject()

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor: decision_actor,
      state_aggregator: state_aggregator,
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
  let decision_actor: process.Subject(room_actor.DecisionMessage) =
    process.new_subject()
  let state_aggregator = process.new_subject()

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor: decision_actor,
      state_aggregator: state_aggregator,
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
  let decision_actor: process.Subject(room_actor.DecisionMessage) =
    process.new_subject()
  let state_aggregator = process.new_subject()

  let assert Ok(started) =
    room_actor.start(
      name: "bedroom",
      schedule: make_test_schedule(),
      decision_actor: decision_actor,
      state_aggregator: state_aggregator,
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
  let decision_actor: process.Subject(room_actor.DecisionMessage) =
    process.new_subject()
  let state_aggregator = process.new_subject()

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor: decision_actor,
      state_aggregator: state_aggregator,
    )

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  // Send TRV temperature update
  let temp = temperature.temperature(21.5)
  process.send(started.data, room_actor.TrvTemperatureChanged(trv_id, temp))

  // Decision actor should receive notification
  let assert Ok(msg) = process.receive(decision_actor, 1000)
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
  let decision_actor: process.Subject(room_actor.DecisionMessage) =
    process.new_subject()
  let state_aggregator = process.new_subject()

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor: decision_actor,
      state_aggregator: state_aggregator,
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
  let decision_actor: process.Subject(room_actor.DecisionMessage) =
    process.new_subject()
  let state_aggregator = process.new_subject()

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor: decision_actor,
      state_aggregator: state_aggregator,
    )

  // Send house mode change
  process.send(
    started.data,
    room_actor.HouseModeChanged(mode.HouseModeSleeping),
  )

  // Decision actor should receive notification
  let assert Ok(msg) = process.receive(decision_actor, 1000)
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
  let decision_actor: process.Subject(room_actor.DecisionMessage) =
    process.new_subject()
  let state_aggregator = process.new_subject()

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor: decision_actor,
      state_aggregator: state_aggregator,
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
  let decision_actor: process.Subject(room_actor.DecisionMessage) =
    process.new_subject()
  let state_aggregator = process.new_subject()

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor: decision_actor,
      state_aggregator: state_aggregator,
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
  let decision_actor: process.Subject(room_actor.DecisionMessage) =
    process.new_subject()
  let state_aggregator = process.new_subject()

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor: decision_actor,
      state_aggregator: state_aggregator,
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
  let decision_actor: process.Subject(room_actor.DecisionMessage) =
    process.new_subject()
  let state_aggregator = process.new_subject()

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor: decision_actor,
      state_aggregator: state_aggregator,
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
  let decision_actor: process.Subject(room_actor.DecisionMessage) =
    process.new_subject()
  let state_aggregator = process.new_subject()

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor: decision_actor,
      state_aggregator: state_aggregator,
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
  let decision_actor: process.Subject(room_actor.DecisionMessage) =
    process.new_subject()
  let state_aggregator = process.new_subject()

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor: decision_actor,
      state_aggregator: state_aggregator,
    )

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  // Send TRV mode update
  process.send(started.data, room_actor.TrvModeChanged(trv_id, mode.HvacHeat))

  // Decision actor should receive notification
  let assert Ok(msg) = process.receive(decision_actor, 1000)
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
  let decision_actor: process.Subject(room_actor.DecisionMessage) =
    process.new_subject()
  let state_aggregator = process.new_subject()

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor: decision_actor,
      state_aggregator: state_aggregator,
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
  let decision_actor: process.Subject(room_actor.DecisionMessage) =
    process.new_subject()
  let state_aggregator = process.new_subject()

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor: decision_actor,
      state_aggregator: state_aggregator,
    )

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  // Send TRV is_heating update
  process.send(started.data, room_actor.TrvIsHeatingChanged(trv_id, True))

  // Decision actor should receive notification
  let assert Ok(msg) = process.receive(decision_actor, 1000)
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
  let decision_actor: process.Subject(room_actor.DecisionMessage) =
    process.new_subject()
  let state_aggregator = process.new_subject()

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor: decision_actor,
      state_aggregator: state_aggregator,
    )

  // Query state
  let reply_subject = process.new_subject()
  process.send(started.data, room_actor.GetState(reply_subject))
  let assert Ok(state) = process.receive(reply_subject, 1000)

  // Target temperature should be computed (not None)
  state.target_temperature |> option.is_some |> should.be_true
}

pub fn room_actor_recomputes_target_on_house_mode_change_test() {
  let decision_actor: process.Subject(room_actor.DecisionMessage) =
    process.new_subject()
  let state_aggregator = process.new_subject()

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor: decision_actor,
      state_aggregator: state_aggregator,
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
  let decision_actor: process.Subject(room_actor.DecisionMessage) =
    process.new_subject()
  let state_aggregator = process.new_subject()

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor: decision_actor,
      state_aggregator: state_aggregator,
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
  let decision_actor: process.Subject(room_actor.DecisionMessage) =
    process.new_subject()
  let state_aggregator: process.Subject(room_actor.AggregatorMessage) =
    process.new_subject()

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor: decision_actor,
      state_aggregator: state_aggregator,
    )

  let assert Ok(trv_id) = entity_id.climate_entity_id("climate.lounge_trv")

  // Send TRV temperature update
  let temp = temperature.temperature(21.5)
  process.send(started.data, room_actor.TrvTemperatureChanged(trv_id, temp))

  // State aggregator should receive notification
  let assert Ok(msg) = process.receive(state_aggregator, 1000)
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
  let decision_actor = process.new_subject()
  let state_aggregator = process.new_subject()

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor: decision_actor,
      state_aggregator: state_aggregator,
    )

  let reply_subject = process.new_subject()
  process.send(started.data, room_actor.GetState(reply_subject))
  let assert Ok(state) = process.receive(reply_subject, 1000)

  state.room_mode |> should.equal(mode.RoomModeAuto)
}

pub fn room_actor_room_mode_is_off_when_any_trv_off_test() {
  // If any TRV has HvacOff mode, room_mode should be RoomModeOff
  let decision_actor: process.Subject(room_actor.DecisionMessage) =
    process.new_subject()
  let state_aggregator = process.new_subject()

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor: decision_actor,
      state_aggregator: state_aggregator,
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
  let decision_actor: process.Subject(room_actor.DecisionMessage) =
    process.new_subject()
  let state_aggregator = process.new_subject()

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor: decision_actor,
      state_aggregator: state_aggregator,
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
  let decision_actor: process.Subject(room_actor.DecisionMessage) =
    process.new_subject()
  let state_aggregator = process.new_subject()

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor: decision_actor,
      state_aggregator: state_aggregator,
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
  let decision_actor: process.Subject(room_actor.DecisionMessage) =
    process.new_subject()
  let state_aggregator = process.new_subject()

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor: decision_actor,
      state_aggregator: state_aggregator,
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
  let decision_actor: process.Subject(room_actor.DecisionMessage) =
    process.new_subject()
  let state_aggregator = process.new_subject()

  let assert Ok(started) =
    room_actor.start(
      name: "lounge",
      schedule: make_test_schedule(),
      decision_actor: decision_actor,
      state_aggregator: state_aggregator,
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
