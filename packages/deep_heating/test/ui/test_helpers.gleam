//// Test helper utilities for UI component testing.
////
//// Provides reusable test fixtures for RoomState, DeepHeatingState,
//// and other UI-related types.

import deep_heating/mode.{RoomModeAuto, RoomModeOff, RoomModeSleeping}
import deep_heating/state.{
  type DeepHeatingState, type RoomState, DeepHeatingState, RoomState,
  TemperatureReading,
}
import deep_heating/temperature
import gleam/option.{None, Some}

/// Create a room that is currently heating.
pub fn heating_room() -> RoomState {
  RoomState(
    name: "Test Room",
    temperature: Some(TemperatureReading(
      temperature: temperature.temperature(20.0),
      time: 0,
    )),
    target_temperature: Some(temperature.temperature(22.0)),
    radiators: [],
    mode: Some(RoomModeAuto),
    is_heating: Some(True),
    adjustment: 0.0,
  )
}

/// Create a room that is not heating (cooling/idle).
pub fn cooling_room() -> RoomState {
  RoomState(..heating_room(), is_heating: Some(False))
}

/// Create a room with unknown heating status.
pub fn unknown_room() -> RoomState {
  RoomState(..heating_room(), is_heating: None)
}

/// Create a room that is turned off.
pub fn off_room() -> RoomState {
  RoomState(
    ..heating_room(),
    mode: Some(RoomModeOff),
    target_temperature: None,
    is_heating: Some(False),
  )
}

/// Create a room in sleeping mode.
pub fn sleeping_room() -> RoomState {
  RoomState(
    ..heating_room(),
    mode: Some(RoomModeSleeping),
    target_temperature: Some(temperature.temperature(18.0)),
    is_heating: Some(False),
  )
}

/// Create a room with a temperature adjustment.
pub fn adjusted_room(adjustment: Float) -> RoomState {
  RoomState(..heating_room(), adjustment: adjustment)
}

/// Create a room with a specific name and temperature.
pub fn room_with_temp(name: String, temp: Float) -> RoomState {
  RoomState(
    ..heating_room(),
    name: name,
    temperature: Some(TemperatureReading(
      temperature: temperature.temperature(temp),
      time: 0,
    )),
  )
}

/// Create a room without a temperature reading.
pub fn room_without_temp(name: String) -> RoomState {
  RoomState(..heating_room(), name: name, temperature: None)
}

/// Create a room without a target temperature (e.g., turned off room).
pub fn room_without_target() -> RoomState {
  RoomState(..heating_room(), target_temperature: None, is_heating: Some(False))
}

// ============================================================================
// DeepHeatingState Test Helpers
// ============================================================================

/// Create a sample state with one heating room.
pub fn sample_state() -> DeepHeatingState {
  DeepHeatingState(rooms: [heating_room()], is_heating: Some(False))
}

/// Create a state where heating is active.
pub fn state_heating_active() -> DeepHeatingState {
  DeepHeatingState(rooms: [heating_room()], is_heating: Some(True))
}

/// Create a state with multiple rooms at different temperatures.
pub fn state_with_multiple_rooms() -> DeepHeatingState {
  DeepHeatingState(
    rooms: [
      room_with_temp("Cold Room", 15.0),
      room_with_temp("Hot Room", 25.0),
      room_with_temp("Medium Room", 20.0),
    ],
    is_heating: Some(False),
  )
}

/// Create a state with a single room in auto mode.
pub fn state_with_auto_room() -> DeepHeatingState {
  DeepHeatingState(rooms: [heating_room()], is_heating: Some(True))
}

/// Create a state from a list of rooms.
pub fn state_with_rooms(rooms: List(RoomState)) -> DeepHeatingState {
  DeepHeatingState(rooms: rooms, is_heating: Some(False))
}
