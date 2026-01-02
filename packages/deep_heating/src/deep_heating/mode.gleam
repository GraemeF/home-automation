/// House-wide operating mode.
pub type HouseMode {
  HouseModeAuto
  HouseModeSleeping
}

/// Per-room operating mode.
pub type RoomMode {
  RoomModeOff
  RoomModeAuto
  RoomModeSleeping
}

/// HVAC mode for TRVs (matches Home Assistant climate modes).
pub type HvacMode {
  HvacOff
  HvacHeat
  HvacAuto
}

// HouseMode serialization

/// Convert HouseMode to string for JSON/API.
pub fn house_mode_to_string(mode: HouseMode) -> String {
  case mode {
    HouseModeAuto -> "Auto"
    HouseModeSleeping -> "Sleeping"
  }
}

/// Parse HouseMode from string.
pub fn house_mode_from_string(s: String) -> Result(HouseMode, String) {
  case s {
    "Auto" -> Ok(HouseModeAuto)
    "Sleeping" -> Ok(HouseModeSleeping)
    _ -> Error("Invalid house mode: " <> s)
  }
}

// RoomMode serialization

/// Convert RoomMode to string for JSON/API.
pub fn room_mode_to_string(mode: RoomMode) -> String {
  case mode {
    RoomModeOff -> "Off"
    RoomModeAuto -> "Auto"
    RoomModeSleeping -> "Sleeping"
  }
}

/// Parse RoomMode from string.
pub fn room_mode_from_string(s: String) -> Result(RoomMode, String) {
  case s {
    "Off" -> Ok(RoomModeOff)
    "Auto" -> Ok(RoomModeAuto)
    "Sleeping" -> Ok(RoomModeSleeping)
    _ -> Error("Invalid room mode: " <> s)
  }
}

// HvacMode serialization (lowercase to match Home Assistant API)

/// Convert HvacMode to string for Home Assistant API.
pub fn hvac_mode_to_string(mode: HvacMode) -> String {
  case mode {
    HvacOff -> "off"
    HvacHeat -> "heat"
    HvacAuto -> "auto"
  }
}

/// Parse HvacMode from Home Assistant API string.
pub fn hvac_mode_from_string(s: String) -> Result(HvacMode, String) {
  case s {
    "off" -> Ok(HvacOff)
    "heat" -> Ok(HvacHeat)
    "auto" -> Ok(HvacAuto)
    _ -> Error("Invalid HVAC mode: " <> s)
  }
}

// Conversions between modes

/// Convert HouseMode to the corresponding RoomMode.
pub fn house_mode_to_room_mode(mode: HouseMode) -> RoomMode {
  case mode {
    HouseModeAuto -> RoomModeAuto
    HouseModeSleeping -> RoomModeSleeping
  }
}
