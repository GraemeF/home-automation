//// Test helper utilities for UI component testing.
////
//// Provides reusable test fixtures for RoomState and other UI-related types.

import deep_heating/mode.{RoomModeAuto, RoomModeOff}
import deep_heating/state.{type RoomState, RoomState, TemperatureReading}
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

/// Create a room with a temperature adjustment.
pub fn adjusted_room(adjustment: Float) -> RoomState {
  RoomState(..heating_room(), adjustment: adjustment)
}
