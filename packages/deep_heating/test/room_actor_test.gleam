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
