import gleam/string

/// Opaque type for Home Assistant climate entity IDs.
/// Must start with "climate."
pub opaque type ClimateEntityId {
  ClimateEntityId(String)
}

/// Create a ClimateEntityId from a string, validating the prefix.
pub fn climate_entity_id(id: String) -> Result(ClimateEntityId, String) {
  case string.starts_with(id, "climate.") {
    True -> Ok(ClimateEntityId(id))
    False -> Error("Climate entity ID must start with 'climate.'")
  }
}

/// Extract the raw string from a ClimateEntityId.
pub fn climate_entity_id_to_string(id: ClimateEntityId) -> String {
  let ClimateEntityId(value) = id
  value
}

/// Opaque type for Home Assistant sensor entity IDs.
/// Must start with "sensor."
pub opaque type SensorEntityId {
  SensorEntityId(String)
}

/// Create a SensorEntityId from a string, validating the prefix.
pub fn sensor_entity_id(id: String) -> Result(SensorEntityId, String) {
  case string.starts_with(id, "sensor.") {
    True -> Ok(SensorEntityId(id))
    False -> Error("Sensor entity ID must start with 'sensor.'")
  }
}

/// Extract the raw string from a SensorEntityId.
pub fn sensor_entity_id_to_string(id: SensorEntityId) -> String {
  let SensorEntityId(value) = id
  value
}

/// Opaque type for Home Assistant goodnight button entity IDs.
/// Must start with "event." or "input_button."
pub opaque type GoodnightEntityId {
  GoodnightEntityId(String)
}

/// Create a GoodnightEntityId from a string, validating the prefix.
pub fn goodnight_entity_id(id: String) -> Result(GoodnightEntityId, String) {
  case
    string.starts_with(id, "event.") || string.starts_with(id, "input_button.")
  {
    True -> Ok(GoodnightEntityId(id))
    False ->
      Error("Goodnight entity ID must start with 'event.' or 'input_button.'")
  }
}

/// Extract the raw string from a GoodnightEntityId.
pub fn goodnight_entity_id_to_string(id: GoodnightEntityId) -> String {
  let GoodnightEntityId(value) = id
  value
}
