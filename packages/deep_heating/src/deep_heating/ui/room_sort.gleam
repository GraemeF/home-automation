//// Room sorting utilities for UI display.

import deep_heating/state.{type RoomState}
import deep_heating/temperature.{type Temperature}
import gleam/list
import gleam/option.{None, Some}
import gleam/order.{type Order}

/// Sort rooms by temperature, hottest first.
pub fn sort_by_temperature(rooms: List(RoomState)) -> List(RoomState) {
  list.sort(rooms, compare_by_temperature)
}

/// Compare rooms by temperature for sorting (hottest first).
pub fn compare_by_temperature(a: RoomState, b: RoomState) -> Order {
  let a_temp = get_room_temp_or_min(a)
  let b_temp = get_room_temp_or_min(b)
  // Descending order - b before a for hottest first
  temperature.compare(b_temp, a_temp)
}

fn get_room_temp_or_min(room: RoomState) -> Temperature {
  case room.temperature {
    Some(reading) -> reading.temperature
    // Rooms without temp sort to end - since hottest first (descending),
    // use very low value so they appear at the end
    None -> temperature.temperature(-999.0)
  }
}
