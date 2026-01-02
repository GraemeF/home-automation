import gleeunit/should
import deep_heating/mode.{
  HouseModeAuto, HouseModeSleeping,
  RoomModeOff, RoomModeAuto, RoomModeSleeping,
  HvacOff, HvacHeat, HvacAuto,
  house_mode_to_string, house_mode_from_string,
  room_mode_to_string, room_mode_from_string,
  hvac_mode_to_string, hvac_mode_from_string,
  house_mode_to_room_mode,
}

// HouseMode tests

pub fn house_mode_auto_to_string_test() {
  HouseModeAuto |> house_mode_to_string |> should.equal("Auto")
}

pub fn house_mode_sleeping_to_string_test() {
  HouseModeSleeping |> house_mode_to_string |> should.equal("Sleeping")
}

pub fn house_mode_from_string_auto_test() {
  house_mode_from_string("Auto") |> should.equal(Ok(HouseModeAuto))
}

pub fn house_mode_from_string_sleeping_test() {
  house_mode_from_string("Sleeping") |> should.equal(Ok(HouseModeSleeping))
}

pub fn house_mode_from_string_invalid_test() {
  house_mode_from_string("Invalid") |> should.be_error
}

// RoomMode tests

pub fn room_mode_off_to_string_test() {
  RoomModeOff |> room_mode_to_string |> should.equal("Off")
}

pub fn room_mode_auto_to_string_test() {
  RoomModeAuto |> room_mode_to_string |> should.equal("Auto")
}

pub fn room_mode_sleeping_to_string_test() {
  RoomModeSleeping |> room_mode_to_string |> should.equal("Sleeping")
}

pub fn room_mode_from_string_off_test() {
  room_mode_from_string("Off") |> should.equal(Ok(RoomModeOff))
}

pub fn room_mode_from_string_auto_test() {
  room_mode_from_string("Auto") |> should.equal(Ok(RoomModeAuto))
}

pub fn room_mode_from_string_sleeping_test() {
  room_mode_from_string("Sleeping") |> should.equal(Ok(RoomModeSleeping))
}

pub fn room_mode_from_string_invalid_test() {
  room_mode_from_string("Invalid") |> should.be_error
}

// HvacMode tests

pub fn hvac_mode_off_to_string_test() {
  HvacOff |> hvac_mode_to_string |> should.equal("off")
}

pub fn hvac_mode_heat_to_string_test() {
  HvacHeat |> hvac_mode_to_string |> should.equal("heat")
}

pub fn hvac_mode_auto_to_string_test() {
  HvacAuto |> hvac_mode_to_string |> should.equal("auto")
}

pub fn hvac_mode_from_string_off_test() {
  hvac_mode_from_string("off") |> should.equal(Ok(HvacOff))
}

pub fn hvac_mode_from_string_heat_test() {
  hvac_mode_from_string("heat") |> should.equal(Ok(HvacHeat))
}

pub fn hvac_mode_from_string_auto_test() {
  hvac_mode_from_string("auto") |> should.equal(Ok(HvacAuto))
}

pub fn hvac_mode_from_string_invalid_test() {
  hvac_mode_from_string("invalid") |> should.be_error
}

// Conversion tests

pub fn house_mode_auto_converts_to_room_mode_auto_test() {
  HouseModeAuto |> house_mode_to_room_mode |> should.equal(RoomModeAuto)
}

pub fn house_mode_sleeping_converts_to_room_mode_sleeping_test() {
  HouseModeSleeping |> house_mode_to_room_mode |> should.equal(RoomModeSleeping)
}
