import deep_heating/actor/house_mode_actor
import deep_heating/actor/room_actor
import deep_heating/mode
import gleam/erlang/process
import gleeunit/should

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
  let assert Ok(actor) = house_mode_actor.start_link()

  // Press sleep button
  process.send(actor, house_mode_actor.SleepButtonPressed)

  process.sleep(10)

  // Query mode
  let reply_subject = process.new_subject()
  process.send(actor, house_mode_actor.GetMode(reply_subject))

  let assert Ok(mode) = process.receive(reply_subject, 1000)
  mode |> should.equal(mode.HouseModeSleeping)
}

pub fn house_mode_actor_transitions_to_auto_on_wakeup_test() {
  let assert Ok(actor) = house_mode_actor.start_link()

  // Go to sleep first
  process.send(actor, house_mode_actor.SleepButtonPressed)
  process.sleep(10)

  // Wake up
  process.send(actor, house_mode_actor.WakeUp)
  process.sleep(10)

  let reply_subject = process.new_subject()
  process.send(actor, house_mode_actor.GetMode(reply_subject))

  let assert Ok(mode) = process.receive(reply_subject, 1000)
  mode |> should.equal(mode.HouseModeAuto)
}

// =============================================================================
// Room Actor Registration and Broadcasting Tests
// =============================================================================

pub fn house_mode_actor_accepts_room_registration_test() {
  let assert Ok(actor) = house_mode_actor.start_link()

  // Create a subject that can receive HouseModeChanged messages
  let room_listener: process.Subject(room_actor.Message) = process.new_subject()

  // Register the room actor - should not crash
  process.send(actor, house_mode_actor.RegisterRoomActor(room_listener))

  process.sleep(10)

  // Actor should still be alive
  let reply_subject = process.new_subject()
  process.send(actor, house_mode_actor.GetMode(reply_subject))
  let assert Ok(_) = process.receive(reply_subject, 1000)
}

pub fn house_mode_actor_broadcasts_sleeping_to_registered_rooms_test() {
  let assert Ok(actor) = house_mode_actor.start_link()

  // Create a room listener
  let room_listener: process.Subject(room_actor.Message) = process.new_subject()

  // Register the room actor
  process.send(actor, house_mode_actor.RegisterRoomActor(room_listener))
  process.sleep(10)

  // Press sleep button
  process.send(actor, house_mode_actor.SleepButtonPressed)

  // Room should receive HouseModeChanged(Sleeping)
  let assert Ok(msg) = process.receive(room_listener, 1000)
  case msg {
    room_actor.HouseModeChanged(mode) -> {
      mode |> should.equal(mode.HouseModeSleeping)
    }
    _ -> should.fail()
  }
}

pub fn house_mode_actor_broadcasts_auto_on_wakeup_test() {
  let assert Ok(actor) = house_mode_actor.start_link()

  // Create a room listener
  let room_listener: process.Subject(room_actor.Message) = process.new_subject()

  // Register the room actor
  process.send(actor, house_mode_actor.RegisterRoomActor(room_listener))
  process.sleep(10)

  // Go to sleep first
  process.send(actor, house_mode_actor.SleepButtonPressed)
  // Consume the sleeping message
  let assert Ok(_) = process.receive(room_listener, 1000)

  // Wake up
  process.send(actor, house_mode_actor.WakeUp)

  // Room should receive HouseModeChanged(Auto)
  let assert Ok(msg) = process.receive(room_listener, 1000)
  case msg {
    room_actor.HouseModeChanged(mode) -> {
      mode |> should.equal(mode.HouseModeAuto)
    }
    _ -> should.fail()
  }
}

pub fn house_mode_actor_broadcasts_to_multiple_rooms_test() {
  let assert Ok(actor) = house_mode_actor.start_link()

  // Create two room listeners
  let room1: process.Subject(room_actor.Message) = process.new_subject()
  let room2: process.Subject(room_actor.Message) = process.new_subject()

  // Register both
  process.send(actor, house_mode_actor.RegisterRoomActor(room1))
  process.send(actor, house_mode_actor.RegisterRoomActor(room2))
  process.sleep(10)

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
