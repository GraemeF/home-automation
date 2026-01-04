import deep_heating/actor/room_actor
import deep_heating/actor/state_aggregator_actor
import deep_heating/state
import deep_heating/temperature
import gleam/erlang/process
import gleam/list
import gleam/option
import gleeunit/should

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

// =============================================================================
// Room Update Tests
// =============================================================================

pub fn state_aggregator_handles_room_update_test() {
  let assert Ok(actor) = state_aggregator_actor.start_link()

  // Send a room update
  let room_state =
    state.RoomState(
      name: "lounge",
      temperature: option.None,
      target_temperature: option.None,
      radiators: [],
      mode: option.None,
      is_heating: option.None,
      adjustment: 0.0,
    )
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
  let room_state1 =
    state.RoomState(
      name: "lounge",
      temperature: option.None,
      target_temperature: option.None,
      radiators: [],
      mode: option.None,
      is_heating: option.None,
      adjustment: 0.0,
    )
  process.send(actor, state_aggregator_actor.RoomUpdated("lounge", room_state1))
  process.sleep(10)

  // Send updated room state with temperature
  let room_state2 =
    state.RoomState(
      name: "lounge",
      temperature: option.Some(state.TemperatureReading(
        temperature: temperature.temperature(21.5),
        time: 12_345,
      )),
      target_temperature: option.None,
      radiators: [],
      mode: option.None,
      is_heating: option.None,
      adjustment: 0.0,
    )
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

  let room1 =
    state.RoomState(
      name: "lounge",
      temperature: option.None,
      target_temperature: option.None,
      radiators: [],
      mode: option.None,
      is_heating: option.None,
      adjustment: 0.0,
    )
  let room2 =
    state.RoomState(
      name: "bedroom",
      temperature: option.None,
      target_temperature: option.None,
      radiators: [],
      mode: option.None,
      is_heating: option.None,
      adjustment: 0.0,
    )

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
  let assert Ok(actor) = state_aggregator_actor.start_link()

  // Subscribe
  let subscriber: process.Subject(state.DeepHeatingState) =
    process.new_subject()
  process.send(actor, state_aggregator_actor.Subscribe(subscriber))
  process.sleep(10)

  // Send a room update
  let room_state =
    state.RoomState(
      name: "lounge",
      temperature: option.None,
      target_temperature: option.None,
      radiators: [],
      mode: option.None,
      is_heating: option.None,
      adjustment: 0.0,
    )
  process.send(actor, state_aggregator_actor.RoomUpdated("lounge", room_state))

  // Wait for throttle period (100ms) plus buffer
  process.sleep(150)

  // Subscriber should receive the broadcast
  let assert Ok(received_state) = process.receive(subscriber, 1000)
  list.length(received_state.rooms) |> should.equal(1)
}

pub fn state_aggregator_throttles_rapid_updates_test() {
  let assert Ok(actor) = state_aggregator_actor.start_link()

  // Subscribe
  let subscriber: process.Subject(state.DeepHeatingState) =
    process.new_subject()
  process.send(actor, state_aggregator_actor.Subscribe(subscriber))
  process.sleep(10)

  // Send multiple rapid updates
  let room_state1 =
    state.RoomState(
      name: "lounge",
      temperature: option.None,
      target_temperature: option.None,
      radiators: [],
      mode: option.None,
      is_heating: option.None,
      adjustment: 0.0,
    )
  let room_state2 =
    state.RoomState(
      name: "bedroom",
      temperature: option.None,
      target_temperature: option.None,
      radiators: [],
      mode: option.None,
      is_heating: option.None,
      adjustment: 0.0,
    )

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
  let assert Ok(actor) = state_aggregator_actor.start_link()

  let subscriber: process.Subject(state.DeepHeatingState) =
    process.new_subject()

  // Subscribe then immediately unsubscribe
  process.send(actor, state_aggregator_actor.Subscribe(subscriber))
  process.sleep(10)
  process.send(actor, state_aggregator_actor.Unsubscribe(subscriber))
  process.sleep(10)

  // Send a room update
  let room_state =
    state.RoomState(
      name: "lounge",
      temperature: option.None,
      target_temperature: option.None,
      radiators: [],
      mode: option.None,
      is_heating: option.None,
      adjustment: 0.0,
    )
  process.send(actor, state_aggregator_actor.RoomUpdated("lounge", room_state))

  // Wait for throttle period
  process.sleep(150)

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
