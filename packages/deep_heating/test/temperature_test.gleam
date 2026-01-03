import deep_heating/temperature.{
  add, compare, eq, gt, gte, is_calling_for_heat, lt, lte, min_room_target,
  min_trv_target, round_down_half, round_up_half, subtract, temperature, unwrap,
}
import gleam/order
import gleeunit/should

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

// =============================================================================
// Rounding Tests (TRV target temperature rounding to 0.5°C increments)
// =============================================================================

// round_up_half - used when heating is required (errs on side of more heating)

pub fn round_up_half_rounds_exact_values_unchanged_test() {
  // Already on 0.5 boundary - no change needed
  temperature(20.0) |> round_up_half |> unwrap |> should.equal(20.0)
  temperature(20.5) |> round_up_half |> unwrap |> should.equal(20.5)
  temperature(21.0) |> round_up_half |> unwrap |> should.equal(21.0)
}

pub fn round_up_half_rounds_up_to_next_half_test() {
  // Values between .0 and .5 round up to .5
  temperature(20.1) |> round_up_half |> unwrap |> should.equal(20.5)
  temperature(20.2) |> round_up_half |> unwrap |> should.equal(20.5)
  temperature(20.3) |> round_up_half |> unwrap |> should.equal(20.5)
  temperature(20.4) |> round_up_half |> unwrap |> should.equal(20.5)
}

pub fn round_up_half_rounds_up_to_next_whole_test() {
  // Values between .5 and 1.0 round up to next whole number
  temperature(20.6) |> round_up_half |> unwrap |> should.equal(21.0)
  temperature(20.7) |> round_up_half |> unwrap |> should.equal(21.0)
  temperature(20.8) |> round_up_half |> unwrap |> should.equal(21.0)
  temperature(20.9) |> round_up_half |> unwrap |> should.equal(21.0)
}

// round_down_half - used when heating is NOT required (errs on side of less heating)

pub fn round_down_half_rounds_exact_values_unchanged_test() {
  // Already on 0.5 boundary - no change needed
  temperature(20.0) |> round_down_half |> unwrap |> should.equal(20.0)
  temperature(20.5) |> round_down_half |> unwrap |> should.equal(20.5)
  temperature(21.0) |> round_down_half |> unwrap |> should.equal(21.0)
}

pub fn round_down_half_rounds_down_to_prev_whole_test() {
  // Values between .0 and .5 round down to the whole number
  temperature(20.1) |> round_down_half |> unwrap |> should.equal(20.0)
  temperature(20.2) |> round_down_half |> unwrap |> should.equal(20.0)
  temperature(20.3) |> round_down_half |> unwrap |> should.equal(20.0)
  temperature(20.4) |> round_down_half |> unwrap |> should.equal(20.0)
}

pub fn round_down_half_rounds_down_to_prev_half_test() {
  // Values between .5 and 1.0 round down to .5
  temperature(20.6) |> round_down_half |> unwrap |> should.equal(20.5)
  temperature(20.7) |> round_down_half |> unwrap |> should.equal(20.5)
  temperature(20.8) |> round_down_half |> unwrap |> should.equal(20.5)
  temperature(20.9) |> round_down_half |> unwrap |> should.equal(20.5)
}

// =============================================================================
// Synthesised Heating Status Tests
// =============================================================================
// A TRV is "calling for heat" when its target is above its current temperature.
// This is used for UI display, aggregation, and boiler control.

pub fn is_calling_for_heat_true_when_target_above_current_test() {
  // Target 22°C, current 20°C - calling for heat
  let target = temperature(22.0)
  let current = temperature(20.0)
  is_calling_for_heat(target, current) |> should.be_true
}

pub fn is_calling_for_heat_false_when_target_equals_current_test() {
  // Target 20°C, current 20°C - at setpoint, not calling for heat
  let target = temperature(20.0)
  let current = temperature(20.0)
  is_calling_for_heat(target, current) |> should.be_false
}

pub fn is_calling_for_heat_false_when_target_below_current_test() {
  // Target 18°C, current 20°C - room is warmer than target
  let target = temperature(18.0)
  let current = temperature(20.0)
  is_calling_for_heat(target, current) |> should.be_false
}

pub fn is_calling_for_heat_true_for_small_difference_test() {
  // Even a 0.1°C difference means calling for heat
  let target = temperature(20.1)
  let current = temperature(20.0)
  is_calling_for_heat(target, current) |> should.be_true
}
