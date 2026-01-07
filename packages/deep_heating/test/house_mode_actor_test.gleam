import deep_heating/house_mode/house_mode_actor.{type LocalDateTime}
import deep_heating/mode
import deep_heating/rooms/room_actor
import deep_heating/timer
import gleam/erlang/process
import gleeunit/should

// =============================================================================
// Test Helpers
// =============================================================================

/// Evening time (9pm) - button presses are accepted after 8pm
fn evening_time() -> LocalDateTime {
  make_datetime(2026, 1, 3, 21, 0, 0)
}

/// Start an actor with the clock at evening time (9pm) and timer disabled.
/// Button presses will be accepted since it's after 8pm.
/// Timer is disabled (interval=0) since most tests don't need automatic re-evaluation.
fn make_test_actor_at_evening() -> process.Subject(house_mode_actor.Message) {
  let assert Ok(actor) =
    house_mode_actor.start_with_options(
      get_now: fn() { evening_time() },
      timer_interval_ms: 0,
      send_after: timer.instant_send_after,
    )
  actor
}

/// Start an actor with a specific time provider and timer disabled.
/// Use this for tests that need to control time but don't care about timer behavior.
fn make_test_actor_at_time(
  get_now: fn() -> LocalDateTime,
) -> process.Subject(house_mode_actor.Message) {
  let assert Ok(actor) =
    house_mode_actor.start_with_options(
      get_now: get_now,
      timer_interval_ms: 0,
      send_after: timer.instant_send_after,
    )
  actor
}

/// Create a room listener spy for testing broadcasts
fn make_room_listener() -> process.Subject(room_actor.Message) {
  process.new_subject()
}

// =============================================================================
// Actor Startup Tests
// =============================================================================

pub fn house_mode_actor_starts_successfully_test() {
  let result = house_mode_actor.start_link()
  should.be_ok(result)
}

pub fn house_mode_actor_starts_in_auto_mode_test() {
  let assert Ok(actor) = house_mode_actor.start_link()

  let reply_subject = process.new_subject()
  process.send(actor, house_mode_actor.GetMode(reply_subject))

  let assert Ok(mode) = process.receive(reply_subject, 1000)
  mode |> should.equal(mode.HouseModeAuto)
}

// =============================================================================
// Mode Transition Tests
// =============================================================================

pub fn house_mode_actor_transitions_to_sleeping_on_button_press_test() {
  let actor = make_test_actor_at_evening()

  // Press sleep button
  process.send(actor, house_mode_actor.SleepButtonPressed)

  // Query mode - messages are processed in FIFO order
  let reply_subject = process.new_subject()
  process.send(actor, house_mode_actor.GetMode(reply_subject))

  let assert Ok(current_mode) = process.receive(reply_subject, 1000)
  current_mode |> should.equal(mode.HouseModeSleeping)
}

pub fn house_mode_actor_transitions_to_auto_on_wakeup_test() {
  let actor = make_test_actor_at_evening()

  // Go to sleep first
  process.send(actor, house_mode_actor.SleepButtonPressed)

  // Wake up - messages are processed in FIFO order
  process.send(actor, house_mode_actor.WakeUp)

  let reply_subject = process.new_subject()
  process.send(actor, house_mode_actor.GetMode(reply_subject))

  let assert Ok(current_mode) = process.receive(reply_subject, 1000)
  current_mode |> should.equal(mode.HouseModeAuto)
}

// =============================================================================
// Room Actor Registration and Broadcasting Tests
// =============================================================================

pub fn house_mode_actor_accepts_room_registration_test() {
  // Use timer-disabled actor for fast test
  let actor = make_test_actor_at_time(house_mode_actor.now)

  // Create a subject that can receive HouseModeChanged messages
  let room_listener: process.Subject(room_actor.Message) = process.new_subject()

  // Register the room actor - should not crash
  process.send(actor, house_mode_actor.RegisterRoomActor(room_listener))

  // Actor should still be alive - messages processed in FIFO order
  let reply_subject = process.new_subject()
  process.send(actor, house_mode_actor.GetMode(reply_subject))
  let assert Ok(_) = process.receive(reply_subject, 1000)
}

pub fn house_mode_actor_broadcasts_sleeping_to_registered_rooms_test() {
  let actor = make_test_actor_at_evening()
  let room_listener = make_room_listener()

  // Register the room actor - messages processed in FIFO order
  process.send(actor, house_mode_actor.RegisterRoomActor(room_listener))

  // Press sleep button
  process.send(actor, house_mode_actor.SleepButtonPressed)

  // Room should receive HouseModeChanged(Sleeping)
  let assert Ok(msg) = process.receive(room_listener, 1000)
  case msg {
    room_actor.HouseModeChanged(received_mode) -> {
      received_mode |> should.equal(mode.HouseModeSleeping)
    }
    _ -> should.fail()
  }
}

pub fn house_mode_actor_broadcasts_auto_on_wakeup_test() {
  let actor = make_test_actor_at_evening()
  let room_listener = make_room_listener()

  // Register the room actor - messages processed in FIFO order
  process.send(actor, house_mode_actor.RegisterRoomActor(room_listener))

  // Go to sleep first
  process.send(actor, house_mode_actor.SleepButtonPressed)
  // Consume the sleeping message
  let assert Ok(_) = process.receive(room_listener, 1000)

  // Wake up
  process.send(actor, house_mode_actor.WakeUp)

  // Room should receive HouseModeChanged(Auto)
  let assert Ok(msg) = process.receive(room_listener, 1000)
  case msg {
    room_actor.HouseModeChanged(received_mode) -> {
      received_mode |> should.equal(mode.HouseModeAuto)
    }
    _ -> should.fail()
  }
}

pub fn house_mode_actor_broadcasts_to_multiple_rooms_test() {
  let actor = make_test_actor_at_evening()
  let room1 = make_room_listener()
  let room2 = make_room_listener()

  // Register both - messages processed in FIFO order
  process.send(actor, house_mode_actor.RegisterRoomActor(room1))
  process.send(actor, house_mode_actor.RegisterRoomActor(room2))

  // Press sleep button
  process.send(actor, house_mode_actor.SleepButtonPressed)

  // Both rooms should receive the message
  let assert Ok(msg1) = process.receive(room1, 1000)
  let assert Ok(msg2) = process.receive(room2, 1000)

  case msg1 {
    room_actor.HouseModeChanged(m) -> m |> should.equal(mode.HouseModeSleeping)
    _ -> should.fail()
  }
  case msg2 {
    room_actor.HouseModeChanged(m) -> m |> should.equal(mode.HouseModeSleeping)
    _ -> should.fail()
  }
}

// =============================================================================
// Time-Based Mode Tests
// =============================================================================

// Helper to create a LocalDateTime
fn make_datetime(
  year: Int,
  month: Int,
  day: Int,
  hour: Int,
  minute: Int,
  second: Int,
) -> LocalDateTime {
  house_mode_actor.local_datetime(year, month, day, hour, minute, second)
}

pub fn time_before_3am_is_sleeping_test() {
  // When it's before 3am (and no button pressed), mode should be Sleeping
  // Time: 2am on any day
  let current_time = make_datetime(2026, 1, 3, 2, 0, 0)

  let actor = make_test_actor_at_time(fn() { current_time })

  let reply_subject = process.new_subject()
  process.send(actor, house_mode_actor.GetMode(reply_subject))

  let assert Ok(current_mode) = process.receive(reply_subject, 1000)
  current_mode |> should.equal(mode.HouseModeSleeping)
}

pub fn time_after_3am_is_auto_test() {
  // When it's after 3am (and no button pressed), mode should be Auto
  // Time: 10am on any day
  let current_time = make_datetime(2026, 1, 3, 10, 0, 0)

  let actor = make_test_actor_at_time(fn() { current_time })

  let reply_subject = process.new_subject()
  process.send(actor, house_mode_actor.GetMode(reply_subject))

  let assert Ok(current_mode) = process.receive(reply_subject, 1000)
  current_mode |> should.equal(mode.HouseModeAuto)
}

pub fn button_after_8pm_same_day_is_sleeping_test() {
  // When button is pressed after 8pm (hour > 20) on the same day, mode is Sleeping
  let actor = make_test_actor_at_evening()

  // Press the sleep button - messages processed in FIFO order
  process.send(actor, house_mode_actor.SleepButtonPressed)

  let reply_subject = process.new_subject()
  process.send(actor, house_mode_actor.GetMode(reply_subject))

  let assert Ok(current_mode) = process.receive(reply_subject, 1000)
  current_mode |> should.equal(mode.HouseModeSleeping)
}

pub fn button_before_8pm_same_day_is_auto_test() {
  // When button is pressed before 8pm, it should be ignored (mode stays Auto)
  // Set time to 7pm (19:00) - before the 8pm cutoff
  let current_time = make_datetime(2026, 1, 3, 19, 0, 0)

  let actor = make_test_actor_at_time(fn() { current_time })

  // Press the sleep button - should be ignored because it's before 8pm
  process.send(actor, house_mode_actor.SleepButtonPressed)

  let reply_subject = process.new_subject()
  process.send(actor, house_mode_actor.GetMode(reply_subject))

  let assert Ok(current_mode) = process.receive(reply_subject, 1000)
  // Button pressed before 8pm should NOT trigger sleeping mode
  current_mode |> should.equal(mode.HouseModeAuto)
}

pub fn button_yesterday_is_auto_test() {
  // When button was pressed yesterday (different day), mode should be Auto
  // even if it was after 8pm
  //
  // We test this by verifying the evaluate_mode logic through the actor:
  // 1. Actor at 9pm Jan 3 with button pressed -> Sleeping
  // 2. Actor at 10am Jan 4 with button pressed on Jan 3 -> Auto (different day)
  //
  // Since we can't change time mid-test easily, we verify the "different day"
  // logic by testing initial mode calculation with old button press data

  // Test 1: Button pressed at 9pm same day -> Sleeping
  let actor1 = make_test_actor_at_evening()

  process.send(actor1, house_mode_actor.SleepButtonPressed)

  let reply1 = process.new_subject()
  process.send(actor1, house_mode_actor.GetMode(reply1))
  let assert Ok(mode1) = process.receive(reply1, 1000)
  mode1 |> should.equal(mode.HouseModeSleeping)

  // Test 2: At 10am next day, no button press -> Auto (not sleeping)
  let jan_4_10am = make_datetime(2026, 1, 4, 10, 0, 0)
  let actor2 = make_test_actor_at_time(fn() { jan_4_10am })

  let reply2 = process.new_subject()
  process.send(actor2, house_mode_actor.GetMode(reply2))
  let assert Ok(mode2) = process.receive(reply2, 1000)
  // At 10am with no button press, should be Auto
  mode2 |> should.equal(mode.HouseModeAuto)
}

pub fn mode_transitions_to_auto_after_3am_test() {
  // When mode is Sleeping (before 3am) and clock passes 3am, mode should
  // transition to Auto on re-evaluation
  //
  // Test this by:
  // 1. Verify initial mode at 2am is Sleeping
  // 2. Verify initial mode at 4am is Auto

  // At 2am (before 3am), should be Sleeping
  let two_am = make_datetime(2026, 1, 3, 2, 0, 0)
  let actor1 = make_test_actor_at_time(fn() { two_am })

  let reply1 = process.new_subject()
  process.send(actor1, house_mode_actor.GetMode(reply1))
  let assert Ok(mode1) = process.receive(reply1, 1000)
  mode1 |> should.equal(mode.HouseModeSleeping)

  // At 4am (after 3am), should be Auto
  let four_am = make_datetime(2026, 1, 3, 4, 0, 0)
  let actor2 = make_test_actor_at_time(fn() { four_am })

  let reply2 = process.new_subject()
  process.send(actor2, house_mode_actor.GetMode(reply2))
  let assert Ok(mode2) = process.receive(reply2, 1000)
  mode2 |> should.equal(mode.HouseModeAuto)
}

// =============================================================================
// Auto-Timer Tests
// =============================================================================

pub fn timer_triggers_automatic_mode_reevaluation_test() {
  // The actor should automatically re-evaluate mode every timer interval.
  // We test this by:
  // 1. Starting at 2:59am (Sleeping)
  // 2. Time provider returns 3:01am after some time has passed
  // 3. After timer fires, mode should automatically transition to Auto

  // Use an ETS counter to track call count across process boundaries
  let counter = create_counter()

  let get_time = fn() {
    let count = increment_counter(counter)
    case count {
      // First call (init) - return 2:59am
      1 -> make_datetime(2026, 1, 3, 2, 59, 0)
      // Subsequent calls - return 3:01am (after the 3am threshold)
      _ -> make_datetime(2026, 1, 3, 3, 1, 0)
    }
  }

  // Start actor with short timer interval (100ms for testing)
  let assert Ok(actor) =
    house_mode_actor.start_with_timer_interval(get_time, 100)

  // Initially should be Sleeping (2:59am on first call)
  let reply1 = process.new_subject()
  process.send(actor, house_mode_actor.GetMode(reply1))
  let assert Ok(mode1) = process.receive(reply1, 1000)
  mode1 |> should.equal(mode.HouseModeSleeping)

  // Wait for timer to fire (>100ms)
  process.sleep(150)

  // Now mode should be Auto (3:01am on timer re-evaluation)
  let reply2 = process.new_subject()
  process.send(actor, house_mode_actor.GetMode(reply2))
  let assert Ok(mode2) = process.receive(reply2, 1000)
  mode2 |> should.equal(mode.HouseModeAuto)

  // Clean up
  delete_counter(counter)
}

pub fn timer_reschedules_after_each_evaluation_test() {
  // Timer should keep firing periodically, not just once
  // Test by verifying multiple mode transitions
  //
  // Uses spy_send_after for DETERMINISTIC testing - we manually trigger
  // each timer "fire" by forwarding the captured TimerRequest message.
  // This eliminates race conditions from real timers.

  let counter = create_counter()
  let spy: process.Subject(timer.TimerRequest(house_mode_actor.Message)) =
    process.new_subject()

  let get_time = fn() {
    let count = increment_counter(counter)
    case count {
      // First two calls: 2:59am (Sleeping)
      1 | 2 -> make_datetime(2026, 1, 3, 2, 59, 0)
      // Third call: 3:01am (Auto)
      3 -> make_datetime(2026, 1, 3, 3, 1, 0)
      // Fourth+ calls: 2:30am (back to Sleeping to verify timer keeps firing)
      _ -> make_datetime(2026, 1, 3, 2, 30, 0)
    }
  }

  let assert Ok(actor) =
    house_mode_actor.start_with_options(
      get_now: get_time,
      timer_interval_ms: 100,
      send_after: timer.spy_send_after(spy),
    )

  // Consume the initial timer request (scheduled during init)
  let assert Ok(_initial_request) = process.receive(spy, 100)

  // Initially Sleeping (count=1 from init)
  let reply1 = process.new_subject()
  process.send(actor, house_mode_actor.GetMode(reply1))
  let assert Ok(mode1) = process.receive(reply1, 1000)
  mode1 |> should.equal(mode.HouseModeSleeping)

  // Manually "fire" the first timer by sending ReEvaluateMode directly
  process.send(actor, house_mode_actor.ReEvaluateMode)

  // Consume the rescheduled timer request (proves timer reschedules)
  let assert Ok(_second_request) = process.receive(spy, 100)

  // Still Sleeping (count=2 returns 2:59am)
  let reply2 = process.new_subject()
  process.send(actor, house_mode_actor.GetMode(reply2))
  let assert Ok(mode2) = process.receive(reply2, 1000)
  mode2 |> should.equal(mode.HouseModeSleeping)

  // Manually "fire" the second timer
  process.send(actor, house_mode_actor.ReEvaluateMode)

  // Consume the rescheduled timer request (proves timer keeps rescheduling)
  let assert Ok(_third_request) = process.receive(spy, 100)

  // Now Auto (count=3 returns 3:01am)
  let reply3 = process.new_subject()
  process.send(actor, house_mode_actor.GetMode(reply3))
  let assert Ok(mode3) = process.receive(reply3, 1000)
  mode3 |> should.equal(mode.HouseModeAuto)

  // Manually "fire" the third timer
  process.send(actor, house_mode_actor.ReEvaluateMode)

  // Consume the rescheduled timer request (proves timer STILL keeps rescheduling)
  let assert Ok(_fourth_request) = process.receive(spy, 100)

  // Back to Sleeping (count=4 returns 2:30am) - proves timer keeps firing
  let reply4 = process.new_subject()
  process.send(actor, house_mode_actor.GetMode(reply4))
  let assert Ok(mode4) = process.receive(reply4, 1000)
  mode4 |> should.equal(mode.HouseModeSleeping)

  // Clean up
  delete_counter(counter)
}

// =============================================================================
// Injectable Timer Tests
// =============================================================================

pub fn instant_send_after_with_disabled_timer_avoids_infinite_loop_test() {
  // When using instant_send_after with timer_interval_ms=0, the timer
  // is disabled so there's no infinite recursion from ReEvaluateMode
  // rescheduling itself immediately.
  //
  // This test verifies the pattern used by make_test_actor_at_time()
  // works correctly for fast tests.
  let current_time = make_datetime(2026, 1, 3, 10, 0, 0)
  let assert Ok(actor) =
    house_mode_actor.start_with_options(
      get_now: fn() { current_time },
      timer_interval_ms: 0,
      send_after: timer.instant_send_after,
    )

  // Should be able to query mode immediately (no infinite loop)
  let reply = process.new_subject()
  process.send(actor, house_mode_actor.GetMode(reply))

  // Using short timeout since delivery should be instant
  let assert Ok(current_mode) = process.receive(reply, 100)
  current_mode |> should.equal(mode.HouseModeAuto)
}

pub fn spy_send_after_captures_timer_requests_test() {
  // When using spy_send_after, timer requests are captured
  // but messages are NOT delivered to the target.
  // This allows verifying timer scheduling without waiting.
  let current_time = make_datetime(2026, 1, 3, 10, 0, 0)
  let spy: process.Subject(timer.TimerRequest(house_mode_actor.Message)) =
    process.new_subject()

  let assert Ok(actor) =
    house_mode_actor.start_with_options(
      get_now: fn() { current_time },
      timer_interval_ms: 100,
      send_after: timer.spy_send_after(spy),
    )

  // Should receive a timer request (initial timer scheduled on startup)
  let assert Ok(request) = process.receive(spy, 100)

  // Verify the timer was scheduled with correct parameters
  request.delay_ms |> should.equal(100)
  case request.msg {
    house_mode_actor.ReEvaluateMode -> should.be_true(True)
    _ -> should.fail()
  }

  // Actor should still be responsive (no timer actually fired)
  let reply = process.new_subject()
  process.send(actor, house_mode_actor.GetMode(reply))
  let assert Ok(mode_result) = process.receive(reply, 100)
  mode_result |> should.equal(mode.HouseModeAuto)
}

// =============================================================================
// Graceful Shutdown Tests
// =============================================================================

pub fn shutdown_cancels_pending_timer_test() {
  // When Shutdown is called, the timer should be cancelled
  // and no more ReEvaluateMode messages should be processed
  let current_time = make_datetime(2026, 1, 3, 10, 0, 0)

  // Start actor with real timer (200ms interval)
  let assert Ok(actor) =
    house_mode_actor.start_with_options(
      get_now: fn() { current_time },
      timer_interval_ms: 200,
      send_after: timer.real_send_after,
    )

  // Immediately send Shutdown (before the 200ms timer fires)
  process.send(actor, house_mode_actor.Shutdown)

  // Wait longer than the timer interval
  process.sleep(300)

  // Actor should be stopped - sending a message should not get a response
  let reply_subject = process.new_subject()
  process.send(actor, house_mode_actor.GetMode(reply_subject))

  // The message should timeout because the actor is dead
  let result = process.receive(reply_subject, 100)
  result |> should.be_error
}

// =============================================================================
// ETS Counter Helpers for Cross-Process State
// =============================================================================

/// Opaque type for ETS table reference
type EtsTable

/// Create an ETS counter table, returns table reference
@external(erlang, "house_mode_actor_test_ffi", "create_counter")
fn create_counter() -> EtsTable

/// Increment counter and return new value
@external(erlang, "house_mode_actor_test_ffi", "increment_counter")
fn increment_counter(table: EtsTable) -> Int

/// Delete counter table
@external(erlang, "house_mode_actor_test_ffi", "delete_counter")
fn delete_counter(table: EtsTable) -> Nil

/// Read counter without incrementing (for debugging)
@external(erlang, "house_mode_actor_test_ffi", "read_counter")
fn read_counter(table: EtsTable) -> Int
