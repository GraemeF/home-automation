import gleam/float
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/order.{type Order}

/// Opaque temperature type - cannot be constructed directly.
/// Use the `temperature` smart constructor.
pub opaque type Temperature {
  Temperature(Float)
}

/// Create a Temperature from a Float value.
pub fn temperature(value: Float) -> Temperature {
  Temperature(value)
}

/// Extract the Float value from a Temperature.
pub fn unwrap(temp: Temperature) -> Float {
  let Temperature(value) = temp
  value
}

/// Minimum target temperature for a room (16C).
pub const min_room_target: Temperature = Temperature(16.0)

/// Minimum target temperature for a TRV (5C - frost protection).
pub const min_trv_target: Temperature = Temperature(5.0)

/// Minimum TRV command target (7°C) - lowest setpoint we'll send to a TRV.
pub const min_trv_command_target: Temperature = Temperature(7.0)

/// Maximum TRV command target (32°C) - highest setpoint we'll send to a TRV.
pub const max_trv_command_target: Temperature = Temperature(32.0)

/// Add two temperatures together.
pub fn add(a: Temperature, b: Temperature) -> Temperature {
  Temperature(unwrap(a) +. unwrap(b))
}

/// Subtract temperature b from temperature a.
pub fn subtract(a: Temperature, b: Temperature) -> Temperature {
  Temperature(unwrap(a) -. unwrap(b))
}

/// Compare two temperatures, returning their ordering.
pub fn compare(a: Temperature, b: Temperature) -> Order {
  float.compare(unwrap(a), unwrap(b))
}

/// Check if two temperatures are equal.
pub fn eq(a: Temperature, b: Temperature) -> Bool {
  unwrap(a) == unwrap(b)
}

/// Check if temperature a is greater than temperature b.
pub fn gt(a: Temperature, b: Temperature) -> Bool {
  unwrap(a) >. unwrap(b)
}

/// Check if temperature a is less than temperature b.
pub fn lt(a: Temperature, b: Temperature) -> Bool {
  unwrap(a) <. unwrap(b)
}

/// Check if temperature a is greater than or equal to temperature b.
pub fn gte(a: Temperature, b: Temperature) -> Bool {
  unwrap(a) >=. unwrap(b)
}

/// Check if temperature a is less than or equal to temperature b.
pub fn lte(a: Temperature, b: Temperature) -> Bool {
  unwrap(a) <=. unwrap(b)
}

/// Round temperature UP to nearest 0.5°C increment.
/// Used when heating is required - errs on side of more heating.
/// Formula: ceil(temp * 2) / 2
pub fn round_up_half(temp: Temperature) -> Temperature {
  let value = unwrap(temp)
  Temperature(float.ceiling(value *. 2.0) /. 2.0)
}

/// Round temperature DOWN to nearest 0.5°C increment.
/// Used when heating is NOT required - errs on side of less heating.
/// Formula: floor(temp * 2) / 2
pub fn round_down_half(temp: Temperature) -> Temperature {
  let value = unwrap(temp)
  Temperature(float.floor(value *. 2.0) /. 2.0)
}

/// Determine if a TRV is "calling for heat" based on target and current temps.
/// A TRV calls for heat when target > current.
/// Used for UI display, aggregating heating demand, and boiler control.
pub fn is_calling_for_heat(target: Temperature, current: Temperature) -> Bool {
  gt(target, current)
}

/// Clamp a temperature to be within the given min and max bounds (inclusive).
pub fn clamp(
  temp: Temperature,
  min: Temperature,
  max: Temperature,
) -> Temperature {
  case lt(temp, min) {
    True -> min
    False ->
      case gt(temp, max) {
        True -> max
        False -> temp
      }
  }
}

// =============================================================================
// Formatting Functions (UI display)
// =============================================================================

/// Format a temperature for display.
/// Returns the temperature to 1 decimal place with "°C" suffix.
/// Example: 20.5 -> "20.5°C"
pub fn format(temp: Temperature) -> String {
  float_to_string_1dp(unwrap(temp)) <> "°C"
}

/// Format an optional temperature for display.
/// Returns "–" (en-dash) for None.
pub fn format_option(temp: Option(Temperature)) -> String {
  case temp {
    Some(t) -> format(t)
    None -> "–"
  }
}

/// Format a temperature without units (for use in controls).
pub fn format_bare(temp: Temperature) -> String {
  float_to_string_1dp(unwrap(temp))
}

/// Helper: format float to 1 decimal place.
fn float_to_string_1dp(value: Float) -> String {
  let rounded = int.to_float(float.round(value *. 10.0)) /. 10.0
  let int_part = float.truncate(rounded)
  let frac =
    float.absolute_value(rounded -. int.to_float(int_part)) *. 10.0
    |> float.round
  int.to_string(int_part) <> "." <> int.to_string(frac)
}
