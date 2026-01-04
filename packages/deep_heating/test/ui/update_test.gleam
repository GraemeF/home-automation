import deep_heating/state
import deep_heating/ui/model.{Model}
import deep_heating/ui/msg.{Connected, Disconnected, StateReceived}
import deep_heating/ui/update
import gleam/option.{None, Some}
import gleeunit/should

pub fn connected_sets_connected_true_test() {
  let m = model.init(Nil)
  let updated = update.update(m, Connected)
  should.be_true(updated.connected)
}

pub fn disconnected_sets_connected_false_test() {
  let m = Model(connected: True, state: None)
  let updated = update.update(m, Disconnected)
  should.be_false(updated.connected)
}

pub fn state_received_updates_state_test() {
  let m = model.init(Nil)
  let new_state = state.empty_deep_heating_state()
  let updated = update.update(m, StateReceived(new_state))
  should.equal(updated.state, Some(new_state))
}
