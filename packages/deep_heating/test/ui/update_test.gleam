import deep_heating/mode
import deep_heating/state
import deep_heating/ui/model.{Model}
import deep_heating/ui/msg.{AdjustRoom, Connected, Disconnected, StateReceived}
import deep_heating/ui/update.{Dependencies}
import gleam/dynamic
import gleam/erlang/process
import gleam/option.{None, Some}
import gleeunit/should
import lustre/effect

pub fn connected_sets_connected_true_test() {
  let #(m, _effect) = model.init(Nil)
  let #(updated, _effect) = update.update(m, Connected)
  should.be_true(updated.connected)
}

pub fn disconnected_sets_connected_false_test() {
  let m = Model(connected: True, state: None)
  let #(updated, _effect) = update.update(m, Disconnected)
  should.be_false(updated.connected)
}

pub fn state_received_updates_state_test() {
  let #(m, _effect) = model.init(Nil)
  let new_state = state.empty_deep_heating_state()
  let #(updated, _effect) = update.update(m, StateReceived(new_state))
  should.equal(updated.state, Some(new_state))
}

pub fn adjust_room_does_not_modify_model_test() {
  // Create a model with a room
  let room =
    state.RoomState(
      name: "Living Room",
      temperature: None,
      target_temperature: None,
      radiators: [],
      mode: Some(mode.RoomModeAuto),
      is_heating: None,
      adjustment: 0.0,
    )
  let deep_state = state.DeepHeatingState(rooms: [room], is_heating: None)
  let m = Model(connected: True, state: Some(deep_state))

  // AdjustRoom should not modify the model (state comes from server)
  let #(updated, _effect) = update.update(m, AdjustRoom("Living Room", 0.5))

  // Model should be unchanged
  should.equal(updated, m)
}

pub fn adjust_room_calls_dependency_with_correct_values_test() {
  // Create a model with a room that has adjustment 0.0
  let room =
    state.RoomState(
      name: "Living Room",
      temperature: None,
      target_temperature: None,
      radiators: [],
      mode: Some(mode.RoomModeAuto),
      is_heating: None,
      adjustment: 0.0,
    )
  let deep_state = state.DeepHeatingState(rooms: [room], is_heating: None)
  let m = Model(connected: True, state: Some(deep_state))

  // Use a subject to capture the callback invocation
  let result_subject = process.new_subject()

  let deps =
    Dependencies(adjust_room: fn(name, adj) {
      process.send(result_subject, #(name, adj))
    })

  let update_fn = update.make_update(deps)
  let #(_updated, eff) = update_fn(m, AdjustRoom("Living Room", 0.5))

  // Execute the effect using Lustre's perform function
  effect.perform(
    eff,
    fn(_) { Nil },
    fn(_, _) { Nil },
    fn(_) { Nil },
    fn() { dynamic.nil() },
    fn(_, _) { Nil },
  )

  // Check the callback was called with correct values
  let assert Ok(#(name, adj)) = process.receive(result_subject, 100)
  should.equal(name, "Living Room")
  should.equal(adj, 0.5)
}

pub fn adjust_room_adds_to_existing_adjustment_test() {
  // Create a model with a room that already has adjustment 1.0
  let room =
    state.RoomState(
      name: "Bedroom",
      temperature: None,
      target_temperature: None,
      radiators: [],
      mode: Some(mode.RoomModeAuto),
      is_heating: None,
      adjustment: 1.0,
    )
  let deep_state = state.DeepHeatingState(rooms: [room], is_heating: None)
  let m = Model(connected: True, state: Some(deep_state))

  let result_subject = process.new_subject()
  let deps =
    Dependencies(adjust_room: fn(name, adj) {
      process.send(result_subject, #(name, adj))
    })

  let update_fn = update.make_update(deps)
  let #(_updated, eff) = update_fn(m, AdjustRoom("Bedroom", 0.5))

  effect.perform(
    eff,
    fn(_) { Nil },
    fn(_, _) { Nil },
    fn(_) { Nil },
    fn() { dynamic.nil() },
    fn(_, _) { Nil },
  )

  // Should be 1.0 + 0.5 = 1.5
  let assert Ok(#(name, adj)) = process.receive(result_subject, 100)
  should.equal(name, "Bedroom")
  should.equal(adj, 1.5)
}

pub fn adjust_room_clamps_to_max_test() {
  // Create a room with adjustment already at 2.5
  let room =
    state.RoomState(
      name: "Kitchen",
      temperature: None,
      target_temperature: None,
      radiators: [],
      mode: Some(mode.RoomModeAuto),
      is_heating: None,
      adjustment: 2.5,
    )
  let deep_state = state.DeepHeatingState(rooms: [room], is_heating: None)
  let m = Model(connected: True, state: Some(deep_state))

  let result_subject = process.new_subject()
  let deps =
    Dependencies(adjust_room: fn(_name, adj) {
      process.send(result_subject, adj)
    })

  let update_fn = update.make_update(deps)
  // Try to add 1.0, which would be 3.5, but should clamp to 3.0
  let #(_updated, eff) = update_fn(m, AdjustRoom("Kitchen", 1.0))

  effect.perform(
    eff,
    fn(_) { Nil },
    fn(_, _) { Nil },
    fn(_) { Nil },
    fn() { dynamic.nil() },
    fn(_, _) { Nil },
  )

  let assert Ok(adj) = process.receive(result_subject, 100)
  should.equal(adj, 3.0)
}

pub fn adjust_room_clamps_to_min_test() {
  // Create a room with adjustment already at -2.5
  let room =
    state.RoomState(
      name: "Bathroom",
      temperature: None,
      target_temperature: None,
      radiators: [],
      mode: Some(mode.RoomModeAuto),
      is_heating: None,
      adjustment: -2.5,
    )
  let deep_state = state.DeepHeatingState(rooms: [room], is_heating: None)
  let m = Model(connected: True, state: Some(deep_state))

  let result_subject = process.new_subject()
  let deps =
    Dependencies(adjust_room: fn(_name, adj) {
      process.send(result_subject, adj)
    })

  let update_fn = update.make_update(deps)
  // Try to subtract 1.0, which would be -3.5, but should clamp to -3.0
  let #(_updated, eff) = update_fn(m, AdjustRoom("Bathroom", -1.0))

  effect.perform(
    eff,
    fn(_) { Nil },
    fn(_, _) { Nil },
    fn(_) { Nil },
    fn() { dynamic.nil() },
    fn(_, _) { Nil },
  )

  let assert Ok(adj) = process.receive(result_subject, 100)
  should.equal(adj, -3.0)
}

pub fn adjust_room_defaults_to_zero_when_room_not_found_test() {
  // Empty state - no rooms
  let deep_state = state.DeepHeatingState(rooms: [], is_heating: None)
  let m = Model(connected: True, state: Some(deep_state))

  let result_subject = process.new_subject()
  let deps =
    Dependencies(adjust_room: fn(_name, adj) {
      process.send(result_subject, adj)
    })

  let update_fn = update.make_update(deps)
  let #(_updated, eff) = update_fn(m, AdjustRoom("NonExistent", 0.5))

  effect.perform(
    eff,
    fn(_) { Nil },
    fn(_, _) { Nil },
    fn(_) { Nil },
    fn() { dynamic.nil() },
    fn(_, _) { Nil },
  )

  // Should start from 0.0 + 0.5 = 0.5
  let assert Ok(adj) = process.receive(result_subject, 100)
  should.equal(adj, 0.5)
}

pub fn adjust_room_defaults_to_zero_when_no_state_test() {
  // No state at all
  let m = Model(connected: False, state: None)

  let result_subject = process.new_subject()
  let deps =
    Dependencies(adjust_room: fn(_name, adj) {
      process.send(result_subject, adj)
    })

  let update_fn = update.make_update(deps)
  let #(_updated, eff) = update_fn(m, AdjustRoom("AnyRoom", 1.0))

  effect.perform(
    eff,
    fn(_) { Nil },
    fn(_, _) { Nil },
    fn(_) { Nil },
    fn() { dynamic.nil() },
    fn(_, _) { Nil },
  )

  // Should start from 0.0 + 1.0 = 1.0
  let assert Ok(adj) = process.receive(result_subject, 100)
  should.equal(adj, 1.0)
}
