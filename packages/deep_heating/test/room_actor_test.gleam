import deep_heating/actor/room_actor
import deep_heating/mode
import deep_heating/schedule
import deep_heating/temperature
import gleam/erlang/process
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
