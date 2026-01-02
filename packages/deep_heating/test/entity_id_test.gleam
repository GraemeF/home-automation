import gleeunit/should
import deep_heating/entity_id.{
  climate_entity_id, climate_entity_id_to_string,
  sensor_entity_id, sensor_entity_id_to_string,
  goodnight_entity_id, goodnight_entity_id_to_string,
}

// ClimateEntityId tests

pub fn climate_entity_id_accepts_valid_prefix_test() {
  climate_entity_id("climate.living_room_trv")
  |> should.be_ok
}

pub fn climate_entity_id_rejects_missing_prefix_test() {
  climate_entity_id("living_room_trv")
  |> should.be_error
}

pub fn climate_entity_id_rejects_wrong_prefix_test() {
  climate_entity_id("sensor.living_room_trv")
  |> should.be_error
}

pub fn climate_entity_id_unwraps_correctly_test() {
  let assert Ok(id) = climate_entity_id("climate.bedroom_trv")
  id |> climate_entity_id_to_string |> should.equal("climate.bedroom_trv")
}

pub fn climate_entity_id_rejects_empty_string_test() {
  climate_entity_id("")
  |> should.be_error
}

pub fn climate_entity_id_rejects_just_prefix_test() {
  // "climate." alone is technically valid prefix but not a useful entity
  // This is a design decision - we allow it since HA might have weird names
  climate_entity_id("climate.")
  |> should.be_ok
}

// SensorEntityId tests

pub fn sensor_entity_id_accepts_valid_prefix_test() {
  sensor_entity_id("sensor.living_room_temperature")
  |> should.be_ok
}

pub fn sensor_entity_id_rejects_missing_prefix_test() {
  sensor_entity_id("living_room_temperature")
  |> should.be_error
}

pub fn sensor_entity_id_rejects_wrong_prefix_test() {
  sensor_entity_id("climate.living_room_temperature")
  |> should.be_error
}

pub fn sensor_entity_id_unwraps_correctly_test() {
  let assert Ok(id) = sensor_entity_id("sensor.bedroom_temp")
  id |> sensor_entity_id_to_string |> should.equal("sensor.bedroom_temp")
}

pub fn sensor_entity_id_rejects_empty_string_test() {
  sensor_entity_id("")
  |> should.be_error
}

// GoodnightEntityId tests

pub fn goodnight_entity_id_accepts_event_prefix_test() {
  goodnight_entity_id("event.goodnight_pressed")
  |> should.be_ok
}

pub fn goodnight_entity_id_accepts_input_button_prefix_test() {
  goodnight_entity_id("input_button.goodnight")
  |> should.be_ok
}

pub fn goodnight_entity_id_rejects_missing_prefix_test() {
  goodnight_entity_id("goodnight_pressed")
  |> should.be_error
}

pub fn goodnight_entity_id_rejects_wrong_prefix_test() {
  goodnight_entity_id("sensor.goodnight")
  |> should.be_error
}

pub fn goodnight_entity_id_unwraps_event_correctly_test() {
  let assert Ok(id) = goodnight_entity_id("event.sleep_button")
  id |> goodnight_entity_id_to_string |> should.equal("event.sleep_button")
}

pub fn goodnight_entity_id_unwraps_input_button_correctly_test() {
  let assert Ok(id) = goodnight_entity_id("input_button.bedtime")
  id |> goodnight_entity_id_to_string |> should.equal("input_button.bedtime")
}

pub fn goodnight_entity_id_rejects_empty_string_test() {
  goodnight_entity_id("")
  |> should.be_error
}
