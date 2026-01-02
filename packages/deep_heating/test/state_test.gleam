import gleam/option.{None, Some}
import gleeunit/should
import deep_heating/temperature.{temperature}
import deep_heating/mode.{RoomModeAuto}
import deep_heating/state.{
  TemperatureReading, RadiatorState, RoomState, DeepHeatingState,
}

// TemperatureReading tests

pub fn temperature_reading_construction_test() {
  let reading = TemperatureReading(
    temperature: temperature(21.5),
    time: 1704067200,
  )
  reading.time |> should.equal(1704067200)
}

pub fn temperature_reading_temperature_field_test() {
  let reading = TemperatureReading(
    temperature: temperature(19.0),
    time: 1704067200,
  )
  reading.temperature |> temperature.unwrap |> should.equal(19.0)
}

// RadiatorState tests

pub fn radiator_state_construction_test() {
  let radiator = RadiatorState(
    name: "Living Room TRV",
    temperature: None,
    target_temperature: None,
    desired_target_temperature: None,
    is_heating: None,
  )
  radiator.name |> should.equal("Living Room TRV")
}

pub fn radiator_state_with_temperature_test() {
  let reading = TemperatureReading(
    temperature: temperature(20.0),
    time: 1704067200,
  )
  let radiator = RadiatorState(
    name: "Bedroom TRV",
    temperature: Some(reading),
    target_temperature: None,
    desired_target_temperature: None,
    is_heating: Some(True),
  )
  radiator.is_heating |> should.equal(Some(True))
  let assert Some(temp_reading) = radiator.temperature
  temp_reading.temperature |> temperature.unwrap |> should.equal(20.0)
}

pub fn radiator_state_all_fields_test() {
  let current = TemperatureReading(temperature: temperature(18.0), time: 100)
  let target = TemperatureReading(temperature: temperature(21.0), time: 100)
  let desired = TemperatureReading(temperature: temperature(22.0), time: 100)

  let radiator = RadiatorState(
    name: "Kitchen TRV",
    temperature: Some(current),
    target_temperature: Some(target),
    desired_target_temperature: Some(desired),
    is_heating: Some(True),
  )

  let assert Some(t) = radiator.target_temperature
  t.temperature |> temperature.unwrap |> should.equal(21.0)

  let assert Some(d) = radiator.desired_target_temperature
  d.temperature |> temperature.unwrap |> should.equal(22.0)
}

// RoomState tests

pub fn room_state_construction_test() {
  let room = RoomState(
    name: "Living Room",
    temperature: None,
    target_temperature: None,
    radiators: [],
    mode: None,
    is_heating: None,
    adjustment: 0.0,
  )
  room.name |> should.equal("Living Room")
  room.adjustment |> should.equal(0.0)
}

pub fn room_state_with_radiators_test() {
  let trv1 = RadiatorState(
    name: "TRV 1",
    temperature: None,
    target_temperature: None,
    desired_target_temperature: None,
    is_heating: None,
  )
  let trv2 = RadiatorState(
    name: "TRV 2",
    temperature: None,
    target_temperature: None,
    desired_target_temperature: None,
    is_heating: None,
  )

  let room = RoomState(
    name: "Master Bedroom",
    temperature: None,
    target_temperature: Some(temperature(20.0)),
    radiators: [trv1, trv2],
    mode: Some(RoomModeAuto),
    is_heating: Some(False),
    adjustment: 1.5,
  )

  room.radiators |> should.equal([trv1, trv2])
  room.mode |> should.equal(Some(RoomModeAuto))
  room.adjustment |> should.equal(1.5)
}

pub fn room_state_target_temperature_test() {
  let room = RoomState(
    name: "Office",
    temperature: None,
    target_temperature: Some(temperature(19.0)),
    radiators: [],
    mode: None,
    is_heating: None,
    adjustment: -0.5,
  )

  let assert Some(target) = room.target_temperature
  target |> temperature.unwrap |> should.equal(19.0)
}

// DeepHeatingState tests

pub fn deep_heating_state_empty_test() {
  let state = DeepHeatingState(
    rooms: [],
    is_heating: None,
  )
  state.rooms |> should.equal([])
  state.is_heating |> should.equal(None)
}

pub fn deep_heating_state_with_rooms_test() {
  let room1 = RoomState(
    name: "Living Room",
    temperature: None,
    target_temperature: None,
    radiators: [],
    mode: None,
    is_heating: None,
    adjustment: 0.0,
  )
  let room2 = RoomState(
    name: "Bedroom",
    temperature: None,
    target_temperature: None,
    radiators: [],
    mode: None,
    is_heating: None,
    adjustment: 0.0,
  )

  let state = DeepHeatingState(
    rooms: [room1, room2],
    is_heating: Some(True),
  )

  state.is_heating |> should.equal(Some(True))

  let assert [first, ..] = state.rooms
  first.name |> should.equal("Living Room")
}

pub fn deep_heating_state_nested_structure_test() {
  let reading = TemperatureReading(temperature: temperature(20.5), time: 12345)
  let trv = RadiatorState(
    name: "Lounge TRV",
    temperature: Some(reading),
    target_temperature: None,
    desired_target_temperature: None,
    is_heating: Some(True),
  )
  let room = RoomState(
    name: "Lounge",
    temperature: Some(reading),
    target_temperature: Some(temperature(21.0)),
    radiators: [trv],
    mode: Some(RoomModeAuto),
    is_heating: Some(True),
    adjustment: 0.0,
  )
  let state = DeepHeatingState(
    rooms: [room],
    is_heating: Some(True),
  )

  let assert [r] = state.rooms
  let assert [rad] = r.radiators
  let assert Some(temp) = rad.temperature
  temp.temperature |> temperature.unwrap |> should.equal(20.5)
}
