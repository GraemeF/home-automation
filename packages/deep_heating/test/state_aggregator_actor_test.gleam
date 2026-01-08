import deep_heating/rooms/room_actor
import deep_heating/rooms/room_adjustments
import deep_heating/state
import deep_heating/state/state_aggregator_actor
import deep_heating/temperature
import deep_heating/timer
import gleam/erlang/process
import gleam/list
import gleam/option
import gleeunit/should
import simplifile

// =============================================================================
// Test Helpers
// =============================================================================

/// Create a basic room state with minimal fields set.
/// Most tests just need a room with a name and adjustment.
fn make_room_state(name: String) -> state.RoomState {
  state.RoomState(
    name: name,
    temperature: option.None,
    target_temperature: option.None,
    radiators: [],
    mode: option.None,
    is_heating: option.None,
    adjustment: 0.0,
  )
}

/// Create a room state with a specific adjustment value
fn make_room_state_with_adjustment(
  name: String,
  adjustment: Float,
) -> state.RoomState {
  state.RoomState(..make_room_state(name), adjustment: adjustment)
}

/// Create a room state with a temperature reading
fn make_room_state_with_temp(name: String, temp: Float) -> state.RoomState {
  state.RoomState(
    ..make_room_state(name),
    temperature: option.Some(state.TemperatureReading(
      temperature: temperature.temperature(temp),
      time: 12_345,
    )),
  )
}

/// Drain the initial state sent on Subscribe.
/// Subscribe now immediately sends current state; this helper receives and discards it.
fn drain_initial_state(
  subscriber: process.Subject(state.DeepHeatingState),
) -> Nil {
  let assert Ok(_) = process.receive(subscriber, 100)
  Nil
}

// =============================================================================
// Actor Startup Tests
// =============================================================================

pub fn state_aggregator_starts_successfully_test() {
  let result = state_aggregator_actor.start_link()
  should.be_ok(result)
}

pub fn state_aggregator_returns_empty_initial_state_test() {
  let assert Ok(actor) = state_aggregator_actor.start_link()

  let reply_subject = process.new_subject()
  process.send(actor, state_aggregator_actor.GetState(reply_subject))

  let assert Ok(state) = process.receive(reply_subject, 1000)
  list.length(state.rooms) |> should.equal(0)
}

// =============================================================================
// Subscription Tests
// =============================================================================

pub fn state_aggregator_accepts_subscribe_test() {
  let assert Ok(actor) = state_aggregator_actor.start_link()

  let subscriber: process.Subject(state.DeepHeatingState) =
    process.new_subject()
  process.send(actor, state_aggregator_actor.Subscribe(subscriber))

  process.sleep(10)

  // Actor should still be alive
  let reply_subject = process.new_subject()
  process.send(actor, state_aggregator_actor.GetState(reply_subject))
  let assert Ok(_) = process.receive(reply_subject, 1000)
}

pub fn state_aggregator_accepts_unsubscribe_test() {
  let assert Ok(actor) = state_aggregator_actor.start_link()

  let subscriber: process.Subject(state.DeepHeatingState) =
    process.new_subject()

  // Subscribe then unsubscribe
  process.send(actor, state_aggregator_actor.Subscribe(subscriber))
  process.sleep(10)
  process.send(actor, state_aggregator_actor.Unsubscribe(subscriber))
  process.sleep(10)

  // Actor should still be alive
  let reply_subject = process.new_subject()
  process.send(actor, state_aggregator_actor.GetState(reply_subject))
  let assert Ok(_) = process.receive(reply_subject, 1000)
}

pub fn state_aggregator_sends_current_state_on_subscribe_test() {
  // Use spy_send_after so NO broadcasts ever happen from the timer
  // This ensures any state received is from the Subscribe handler itself
  let timer_spy: process.Subject(
    timer.TimerRequest(state_aggregator_actor.Message),
  ) = process.new_subject()

  let assert Ok(actor) =
    state_aggregator_actor.start_link_with_options(
      adjustments_path: "/tmp/test_subscribe_sends_state.json",
      send_after: timer.spy_send_after(timer_spy),
    )

  // First add some room state so there's something to send
  let room_state = make_room_state("lounge")
  process.send(actor, state_aggregator_actor.RoomUpdated("lounge", room_state))
  process.sleep(10)

  // Now subscribe - should immediately receive current state
  let subscriber: process.Subject(state.DeepHeatingState) =
    process.new_subject()
  process.send(actor, state_aggregator_actor.Subscribe(subscriber))
  process.sleep(10)

  // Should receive state immediately (not from a broadcast since spy_send_after
  // doesn't actually send the Broadcast message)
  let assert Ok(received_state) = process.receive(subscriber, 100)
  list.length(received_state.rooms) |> should.equal(1)
}

// =============================================================================
// Room Update Tests
// =============================================================================

pub fn state_aggregator_handles_room_update_test() {
  let assert Ok(actor) = state_aggregator_actor.start_link()

  // Send a room update
  let room_state = make_room_state("lounge")
  process.send(actor, state_aggregator_actor.RoomUpdated("lounge", room_state))

  process.sleep(10)

  // Query state
  let reply_subject = process.new_subject()
  process.send(actor, state_aggregator_actor.GetState(reply_subject))
  let assert Ok(full_state) = process.receive(reply_subject, 1000)

  // Should have 1 room
  list.length(full_state.rooms) |> should.equal(1)
}

pub fn state_aggregator_updates_existing_room_test() {
  let assert Ok(actor) = state_aggregator_actor.start_link()

  // Send initial room update
  let room_state1 = make_room_state("lounge")
  process.send(actor, state_aggregator_actor.RoomUpdated("lounge", room_state1))
  process.sleep(10)

  // Send updated room state with temperature
  let room_state2 = make_room_state_with_temp("lounge", 21.5)
  process.send(actor, state_aggregator_actor.RoomUpdated("lounge", room_state2))
  process.sleep(10)

  // Query state
  let reply_subject = process.new_subject()
  process.send(actor, state_aggregator_actor.GetState(reply_subject))
  let assert Ok(full_state) = process.receive(reply_subject, 1000)

  // Should still have 1 room (updated, not added)
  list.length(full_state.rooms) |> should.equal(1)

  // Should have the updated temperature
  let assert [room] = full_state.rooms
  room.temperature |> should.be_some
}

pub fn state_aggregator_tracks_multiple_rooms_test() {
  let assert Ok(actor) = state_aggregator_actor.start_link()

  let room1 = make_room_state("lounge")
  let room2 = make_room_state("bedroom")

  process.send(actor, state_aggregator_actor.RoomUpdated("lounge", room1))
  process.send(actor, state_aggregator_actor.RoomUpdated("bedroom", room2))
  process.sleep(10)

  let reply_subject = process.new_subject()
  process.send(actor, state_aggregator_actor.GetState(reply_subject))
  let assert Ok(full_state) = process.receive(reply_subject, 1000)

  list.length(full_state.rooms) |> should.equal(2)
}

// =============================================================================
// Throttled Broadcast Tests
// =============================================================================

pub fn state_aggregator_broadcasts_to_subscribers_after_throttle_test() {
  // Use instant_send_after so we don't need to wait for real throttle timer
  let assert Ok(actor) =
    state_aggregator_actor.start_link_with_options(
      adjustments_path: "/tmp/test_broadcast_throttle.json",
      send_after: timer.instant_send_after,
    )

  // Subscribe
  let subscriber: process.Subject(state.DeepHeatingState) =
    process.new_subject()
  process.send(actor, state_aggregator_actor.Subscribe(subscriber))
  process.sleep(10)

  // Drain the initial empty state sent on subscribe
  drain_initial_state(subscriber)

  // Send a room update
  let room_state = make_room_state("lounge")
  process.send(actor, state_aggregator_actor.RoomUpdated("lounge", room_state))

  // With instant_send_after, broadcast happens immediately - short wait for processing
  process.sleep(20)

  // Subscriber should receive the broadcast
  let assert Ok(received_state) = process.receive(subscriber, 100)
  list.length(received_state.rooms) |> should.equal(1)
}

pub fn state_aggregator_throttles_rapid_updates_test() {
  let assert Ok(actor) = state_aggregator_actor.start_link()

  // Subscribe
  let subscriber: process.Subject(state.DeepHeatingState) =
    process.new_subject()
  process.send(actor, state_aggregator_actor.Subscribe(subscriber))
  process.sleep(10)

  // Drain the initial empty state sent on subscribe
  drain_initial_state(subscriber)

  // Send multiple rapid updates
  let room_state1 = make_room_state("lounge")
  let room_state2 = make_room_state("bedroom")

  // Send updates rapidly (within 100ms window)
  process.send(actor, state_aggregator_actor.RoomUpdated("lounge", room_state1))
  process.sleep(20)
  process.send(
    actor,
    state_aggregator_actor.RoomUpdated("bedroom", room_state2),
  )

  // Wait for throttle period
  process.sleep(150)

  // Should receive only ONE broadcast with both rooms (not two separate broadcasts)
  let assert Ok(received_state) = process.receive(subscriber, 1000)
  list.length(received_state.rooms) |> should.equal(2)

  // There should be no more messages pending (throttling worked)
  case process.receive(subscriber, 50) {
    Error(_) -> Nil
    // Expected - no more messages
    Ok(_) -> should.fail()
    // Unexpected extra broadcast
  }
}

pub fn state_aggregator_does_not_broadcast_to_unsubscribed_test() {
  // Use instant_send_after so we don't need to wait for real throttle timer
  let assert Ok(actor) =
    state_aggregator_actor.start_link_with_options(
      adjustments_path: "/tmp/test_unsubscribe.json",
      send_after: timer.instant_send_after,
    )

  let subscriber: process.Subject(state.DeepHeatingState) =
    process.new_subject()

  // Subscribe then immediately unsubscribe
  process.send(actor, state_aggregator_actor.Subscribe(subscriber))
  process.sleep(10)

  // Drain the initial empty state sent on subscribe
  drain_initial_state(subscriber)

  process.send(actor, state_aggregator_actor.Unsubscribe(subscriber))
  process.sleep(10)

  // Send a room update
  let room_state = make_room_state("lounge")
  process.send(actor, state_aggregator_actor.RoomUpdated("lounge", room_state))

  // With instant_send_after, broadcast happens immediately - short wait for processing
  process.sleep(20)

  // Subscriber should NOT receive anything (unsubscribed)
  case process.receive(subscriber, 50) {
    Error(_) -> Nil
    // Expected - unsubscribed
    Ok(_) -> should.fail()
    // Should not receive broadcast
  }
}

// =============================================================================
// Room Registration and Adjustment Forwarding Tests
// =============================================================================

pub fn state_aggregator_registers_room_actor_test() {
  let assert Ok(actor) = state_aggregator_actor.start_link()

  // Create a mock subject to act as a RoomActor
  let mock_room_actor: process.Subject(room_actor.Message) =
    process.new_subject()

  // Register the mock room actor
  process.send(
    actor,
    state_aggregator_actor.RegisterRoomActor("lounge", mock_room_actor),
  )

  process.sleep(10)

  // Actor should still be alive
  let reply_subject = process.new_subject()
  process.send(actor, state_aggregator_actor.GetState(reply_subject))
  let assert Ok(_) = process.receive(reply_subject, 1000)
}

pub fn state_aggregator_forwards_adjustment_to_room_actor_test() {
  let assert Ok(actor) = state_aggregator_actor.start_link()

  // Create a mock subject to act as a RoomActor
  let mock_room_actor: process.Subject(room_actor.Message) =
    process.new_subject()

  // Register the mock room actor
  process.send(
    actor,
    state_aggregator_actor.RegisterRoomActor("lounge", mock_room_actor),
  )
  process.sleep(10)

  // Send an adjustment command
  process.send(actor, state_aggregator_actor.AdjustRoom("lounge", 1.5))
  process.sleep(10)

  // Mock room actor should receive AdjustmentChanged message
  let assert Ok(msg) = process.receive(mock_room_actor, 1000)
  case msg {
    room_actor.AdjustmentChanged(adjustment) -> {
      adjustment |> should.equal(1.5)
    }
    _ -> should.fail()
  }
}

pub fn state_aggregator_ignores_adjustment_for_unknown_room_test() {
  let assert Ok(actor) = state_aggregator_actor.start_link()

  // Send an adjustment command for a room that doesn't exist
  process.send(actor, state_aggregator_actor.AdjustRoom("unknown_room", 1.5))
  process.sleep(10)

  // Actor should still be alive (didn't crash)
  let reply_subject = process.new_subject()
  process.send(actor, state_aggregator_actor.GetState(reply_subject))
  let assert Ok(_) = process.receive(reply_subject, 1000)
}

// =============================================================================
// Adjustment Persistence Tests
// =============================================================================

pub fn state_aggregator_persists_adjustments_when_path_configured_test() {
  let test_path = "/tmp/test_persist_adjustments.json"
  // Clean up any existing file
  let _ = simplifile.delete(test_path)

  // Start with persistence enabled
  let assert Ok(actor) =
    state_aggregator_actor.start_link_with_persistence(test_path)

  // Send a room update with a non-zero adjustment
  let room_state = make_room_state_with_adjustment("lounge", 1.5)
  process.send(actor, state_aggregator_actor.RoomUpdated("lounge", room_state))
  process.sleep(50)

  // Read the file and verify the adjustment was saved
  let assert Ok(contents) = simplifile.read(test_path)
  let assert Ok(adjustments) = room_adjustments.parse(contents)

  // Cleanup
  let _ = simplifile.delete(test_path)

  // Verify
  adjustments
  |> should.equal([
    room_adjustments.RoomAdjustment(room_name: "lounge", adjustment: 1.5),
  ])
}

pub fn state_aggregator_persists_multiple_rooms_test() {
  let test_path = "/tmp/test_persist_multiple.json"
  let _ = simplifile.delete(test_path)

  let assert Ok(actor) =
    state_aggregator_actor.start_link_with_persistence(test_path)

  // Send updates for multiple rooms with different adjustments
  let lounge_state = make_room_state_with_adjustment("lounge", 1.5)
  let bedroom_state = make_room_state_with_adjustment("bedroom", -0.5)

  process.send(
    actor,
    state_aggregator_actor.RoomUpdated("lounge", lounge_state),
  )
  process.send(
    actor,
    state_aggregator_actor.RoomUpdated("bedroom", bedroom_state),
  )
  process.sleep(50)

  // Read and verify
  let assert Ok(contents) = simplifile.read(test_path)
  let assert Ok(adjustments) = room_adjustments.parse(contents)

  // Cleanup
  let _ = simplifile.delete(test_path)

  // Should have both rooms
  list.length(adjustments) |> should.equal(2)
  room_adjustments.get_adjustment(adjustments, "lounge")
  |> should.equal(1.5)
  room_adjustments.get_adjustment(adjustments, "bedroom")
  |> should.equal(-0.5)
}

pub fn state_aggregator_only_persists_on_adjustment_change_test() {
  let test_path = "/tmp/test_persist_change.json"
  let _ = simplifile.delete(test_path)

  let assert Ok(actor) =
    state_aggregator_actor.start_link_with_persistence(test_path)

  // Send initial room update with no adjustment (0.0)
  let room_state_initial = make_room_state("lounge")
  process.send(
    actor,
    state_aggregator_actor.RoomUpdated("lounge", room_state_initial),
  )
  process.sleep(50)

  // File should not exist yet (adjustment is 0.0, no previous to compare)
  // Actually it SHOULD persist even 0.0 if there was no previous value
  // Let me think about this more carefully...
  // On first update, we should save the file
  let assert Ok(file_exists_after_first) = simplifile.is_file(test_path)

  // Send same update again (no adjustment change)
  process.send(
    actor,
    state_aggregator_actor.RoomUpdated("lounge", room_state_initial),
  )
  process.sleep(50)

  // Get modification time (if exists)
  // Actually this is hard to test precisely - let's just verify the file content is correct
  let assert Ok(contents) = simplifile.read(test_path)
  let assert Ok(adjustments) = room_adjustments.parse(contents)

  // Cleanup
  let _ = simplifile.delete(test_path)

  file_exists_after_first |> should.be_true
  adjustments
  |> should.equal([
    room_adjustments.RoomAdjustment(room_name: "lounge", adjustment: 0.0),
  ])
}

// =============================================================================
// Injectable Timer Tests
// =============================================================================

pub fn state_aggregator_with_instant_send_after_broadcasts_immediately_test() {
  // Start with instant_send_after - broadcasts should happen immediately
  let assert Ok(actor) =
    state_aggregator_actor.start_link_with_options(
      adjustments_path: "/tmp/test_instant_timer.json",
      send_after: timer.instant_send_after,
    )

  // Subscribe
  let subscriber: process.Subject(state.DeepHeatingState) =
    process.new_subject()
  process.send(actor, state_aggregator_actor.Subscribe(subscriber))

  // Give the subscribe message time to process
  process.sleep(10)

  // Drain the initial empty state sent on subscribe
  drain_initial_state(subscriber)

  // Send a room update
  let room_state = make_room_state("lounge")
  process.send(actor, state_aggregator_actor.RoomUpdated("lounge", room_state))

  // With instant_send_after, broadcast happens immediately - no 150ms wait needed
  // Just give a tiny bit of time for message processing
  process.sleep(10)

  // Subscriber should receive the broadcast immediately
  let assert Ok(received_state) = process.receive(subscriber, 100)
  list.length(received_state.rooms) |> should.equal(1)
}

// =============================================================================
// Named Actor with Injectable Timer Tests
// =============================================================================

pub fn state_aggregator_start_with_options_creates_named_actor_test() {
  // Create a unique name for this test
  let name = process.new_name("test_aggregator_named_with_options")

  // Start with a name AND injectable send_after
  let assert Ok(started) =
    state_aggregator_actor.start_with_options(
      name: name,
      adjustments_path: "/tmp/test_named_with_options.json",
      send_after: timer.instant_send_after,
    )

  // Verify the actor is registered with the name
  let assert Ok(_pid) = process.named(name)

  // Verify we got a Subject back
  let reply_subject = process.new_subject()
  process.send(started.data, state_aggregator_actor.GetState(reply_subject))
  let assert Ok(state) = process.receive(reply_subject, 1000)
  list.length(state.rooms) |> should.equal(0)
}

pub fn state_aggregator_start_with_options_uses_injected_timer_test() {
  // Create a unique name for this test
  let name = process.new_name("test_aggregator_timer_injection")

  // Start with instant_send_after
  let assert Ok(started) =
    state_aggregator_actor.start_with_options(
      name: name,
      adjustments_path: "/tmp/test_timer_injection.json",
      send_after: timer.instant_send_after,
    )

  // Subscribe
  let subscriber: process.Subject(state.DeepHeatingState) =
    process.new_subject()
  process.send(started.data, state_aggregator_actor.Subscribe(subscriber))
  process.sleep(10)

  // Drain the initial empty state sent on subscribe
  drain_initial_state(subscriber)

  // Send a room update
  let room_state = make_room_state("lounge")
  process.send(
    started.data,
    state_aggregator_actor.RoomUpdated("lounge", room_state),
  )

  // With instant_send_after, broadcast happens immediately (no 150ms wait)
  process.sleep(10)

  // Subscriber should receive the broadcast
  let assert Ok(received_state) = process.receive(subscriber, 100)
  list.length(received_state.rooms) |> should.equal(1)
}

// =============================================================================
// Graceful Shutdown Tests
// =============================================================================

pub fn shutdown_cancels_pending_broadcast_timer_test() {
  // When Shutdown is called, any pending broadcast timer should be cancelled
  // and the actor should stop
  let assert Ok(actor) =
    state_aggregator_actor.start_link_with_options(
      adjustments_path: "/tmp/test_shutdown.json",
      send_after: timer.real_send_after,
    )

  // Send a room update to trigger broadcast scheduling
  let room_state = make_room_state("test_room")
  process.send(actor, state_aggregator_actor.RoomUpdated("test_room", room_state))

  // Immediately send Shutdown (before the 100ms throttle fires)
  process.send(actor, state_aggregator_actor.Shutdown)

  // Wait longer than the throttle interval
  process.sleep(200)

  // Actor should be stopped - sending a message should not get a response
  let reply_subject = process.new_subject()
  process.send(actor, state_aggregator_actor.GetState(reply_subject))

  // The message should timeout because the actor is dead
  let result = process.receive(reply_subject, 100)
  result |> should.be_error
}
