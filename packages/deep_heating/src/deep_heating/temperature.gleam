import gleam/float
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
