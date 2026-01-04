import deep_heating/ui/model
import gleam/option.{None}
import gleeunit/should

pub fn init_creates_disconnected_model_test() {
  let m = model.init(Nil)
  should.be_false(m.connected)
  should.equal(m.state, None)
}
