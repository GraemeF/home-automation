import gleam/order
import gleeunit/should
import deep_heating/temperature.{
  temperature, unwrap, min_room_target, min_trv_target,
  add, subtract, compare, eq, gt, lt, gte, lte,
}

// Construction tests

pub fn temperature_wraps_float_value_test() {
  let temp = temperature(20.5)
  temp |> unwrap |> should.equal(20.5)
}

pub fn temperature_handles_zero_test() {
  let temp = temperature(0.0)
  temp |> unwrap |> should.equal(0.0)
}

pub fn temperature_handles_negative_test() {
  let temp = temperature(-5.0)
  temp |> unwrap |> should.equal(-5.0)
}

// Constant tests

pub fn min_room_target_is_16_test() {
  min_room_target |> unwrap |> should.equal(16.0)
}

pub fn min_trv_target_is_5_test() {
  min_trv_target |> unwrap |> should.equal(5.0)
}

// Arithmetic tests

pub fn add_temperatures_test() {
  let a = temperature(20.0)
  let b = temperature(2.5)
  add(a, b) |> unwrap |> should.equal(22.5)
}

pub fn subtract_temperatures_test() {
  let a = temperature(20.0)
  let b = temperature(2.5)
  subtract(a, b) |> unwrap |> should.equal(17.5)
}

// Comparison tests

pub fn compare_equal_temperatures_test() {
  let a = temperature(20.0)
  let b = temperature(20.0)
  compare(a, b) |> should.equal(order.Eq)
}

pub fn compare_less_than_test() {
  let a = temperature(18.0)
  let b = temperature(20.0)
  compare(a, b) |> should.equal(order.Lt)
}

pub fn compare_greater_than_test() {
  let a = temperature(22.0)
  let b = temperature(20.0)
  compare(a, b) |> should.equal(order.Gt)
}

pub fn eq_returns_true_for_equal_test() {
  let a = temperature(20.0)
  let b = temperature(20.0)
  eq(a, b) |> should.be_true
}

pub fn eq_returns_false_for_unequal_test() {
  let a = temperature(20.0)
  let b = temperature(21.0)
  eq(a, b) |> should.be_false
}

pub fn gt_returns_true_when_greater_test() {
  let a = temperature(21.0)
  let b = temperature(20.0)
  gt(a, b) |> should.be_true
}

pub fn gt_returns_false_when_less_test() {
  let a = temperature(19.0)
  let b = temperature(20.0)
  gt(a, b) |> should.be_false
}

pub fn lt_returns_true_when_less_test() {
  let a = temperature(19.0)
  let b = temperature(20.0)
  lt(a, b) |> should.be_true
}

pub fn lt_returns_false_when_greater_test() {
  let a = temperature(21.0)
  let b = temperature(20.0)
  lt(a, b) |> should.be_false
}

pub fn gte_returns_true_when_greater_test() {
  let a = temperature(21.0)
  let b = temperature(20.0)
  gte(a, b) |> should.be_true
}

pub fn gte_returns_true_when_equal_test() {
  let a = temperature(20.0)
  let b = temperature(20.0)
  gte(a, b) |> should.be_true
}

pub fn lte_returns_true_when_less_test() {
  let a = temperature(19.0)
  let b = temperature(20.0)
  lte(a, b) |> should.be_true
}

pub fn lte_returns_true_when_equal_test() {
  let a = temperature(20.0)
  let b = temperature(20.0)
  lte(a, b) |> should.be_true
}
