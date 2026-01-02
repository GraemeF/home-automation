import gleam/option.{type Option}
import deep_heating/temperature.{type Temperature}
import deep_heating/mode.{type RoomMode}

/// A temperature reading with a timestamp.
pub type TemperatureReading {
  TemperatureReading(
    temperature: Temperature,
    /// Unix timestamp in seconds
    time: Int,
  )
}

/// State of a single TRV/radiator.
pub type RadiatorState {
  RadiatorState(
    /// Display name of the radiator
    name: String,
    /// Current temperature reading from the TRV
    temperature: Option(TemperatureReading),
    /// Current target temperature the TRV is set to
    target_temperature: Option(TemperatureReading),
    /// Target temperature we want the TRV to be at
    desired_target_temperature: Option(TemperatureReading),
    /// Whether the TRV is currently calling for heat
    is_heating: Option(Bool),
  )
}

/// State of a room containing one or more TRVs.
pub type RoomState {
  RoomState(
    /// Display name of the room
    name: String,
    /// Current temperature from external sensor (more accurate than TRV)
    temperature: Option(TemperatureReading),
    /// Target temperature for the room
    target_temperature: Option(Temperature),
    /// All TRVs in this room
    radiators: List(RadiatorState),
    /// Current operating mode for the room
    mode: Option(RoomMode),
    /// Whether any TRV in the room is calling for heat
    is_heating: Option(Bool),
    /// User adjustment to scheduled temperature (degrees)
    adjustment: Float,
  )
}

/// Top-level state for the entire heating system.
pub type DeepHeatingState {
  DeepHeatingState(
    /// All rooms in the house
    rooms: List(RoomState),
    /// Whether the boiler/heating system is active
    is_heating: Option(Bool),
  )
}
