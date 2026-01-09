import deep_heating/config/home_config
import deep_heating/entity_id
import deep_heating/scheduling/schedule
import deep_heating/temperature
import envoy
import gleam/option.{None, Some}
import gleeunit/should
import simplifile

pub fn parse_minimal_config_test() {
  // Minimal valid config with one room, no schedule
  let json =
    "
    {
      \"rooms\": [
        {
          \"name\": \"Living Area\",
          \"temperatureSensorEntityId\": null,
          \"climateEntityIds\": [\"climate.lounge_radiator\"],
          \"schedule\": null
        }
      ],
      \"sleepSwitchId\": \"input_button.goodnight\",
      \"heatingId\": \"climate.main\"
    }
  "

  let result = home_config.parse(json)

  result |> should.be_ok
  let config = result |> should.be_ok

  // Check top-level fields
  let assert Ok(expected_sleep_switch) =
    entity_id.goodnight_entity_id("input_button.goodnight")
  config.sleep_switch_id |> should.equal(expected_sleep_switch)

  let assert Ok(expected_heating_id) =
    entity_id.climate_entity_id("climate.main")
  config.heating_id |> should.equal(expected_heating_id)

  // Check room
  config.rooms |> should.not_equal([])
  let assert [room, ..] = config.rooms
  room.name |> should.equal("Living Area")
  room.temperature_sensor_entity_id |> should.equal(None)
  room.schedule |> should.equal(None)

  // Check TRV entity IDs
  let assert Ok(expected_trv) =
    entity_id.climate_entity_id("climate.lounge_radiator")
  room.climate_entity_ids |> should.equal([expected_trv])
}

pub fn parse_full_config_test() {
  // Config with temperature sensor and schedule
  let json =
    "
    {
      \"rooms\": [
        {
          \"name\": \"Kitchen\",
          \"temperatureSensorEntityId\": \"sensor.kitchen_temp\",
          \"climateEntityIds\": [\"climate.kitchen_radiator\"],
          \"schedule\": {
            \"monday\": { \"07:00\": 20.0, \"22:00\": 16.0 },
            \"tuesday\": { \"07:00\": 20.0 },
            \"wednesday\": { \"07:00\": 20.0 },
            \"thursday\": { \"07:00\": 20.0 },
            \"friday\": { \"07:00\": 20.0 },
            \"saturday\": { \"08:00\": 19.0 },
            \"sunday\": { \"08:00\": 19.0 }
          }
        }
      ],
      \"sleepSwitchId\": \"event.goodnight\",
      \"heatingId\": \"climate.boiler\"
    }
  "

  let result = home_config.parse(json)
  result |> should.be_ok
  let config = result |> should.be_ok

  let assert [room, ..] = config.rooms
  room.name |> should.equal("Kitchen")

  // Check temperature sensor
  let assert Ok(expected_sensor) =
    entity_id.sensor_entity_id("sensor.kitchen_temp")
  room.temperature_sensor_entity_id |> should.equal(Some(expected_sensor))

  // Check schedule exists
  room.schedule |> should.not_equal(None)
  let assert Some(sched) = room.schedule

  // Verify Monday has correct entries (checking via get_scheduled_temperature)

  // Find the 07:00 entry
  let assert Ok(time_0700) = schedule.time_of_day(7, 0)
  let target_at_0700 =
    schedule.get_scheduled_temperature(sched, schedule.Monday, time_0700)
  target_at_0700 |> should.equal(temperature.temperature(20.0))

  // Find the 22:00 entry
  let assert Ok(time_2200) = schedule.time_of_day(22, 0)
  let target_at_2200 =
    schedule.get_scheduled_temperature(sched, schedule.Monday, time_2200)
  target_at_2200 |> should.equal(temperature.temperature(16.0))
}

pub fn parse_multiple_trvs_test() {
  // Room with multiple TRVs
  let json =
    "
    {
      \"rooms\": [
        {
          \"name\": \"Main Floor\",
          \"temperatureSensorEntityId\": null,
          \"climateEntityIds\": [
            \"climate.lounge_radiator\",
            \"climate.kitchen_radiator\",
            \"climate.hall_radiator\"
          ],
          \"schedule\": null
        }
      ],
      \"sleepSwitchId\": \"input_button.bedtime\",
      \"heatingId\": \"climate.central\"
    }
  "

  let result = home_config.parse(json)
  result |> should.be_ok
  let config = result |> should.be_ok

  let assert [room, ..] = config.rooms
  room.climate_entity_ids
  |> should.equal([
    entity_id.climate_entity_id("climate.lounge_radiator") |> should.be_ok,
    entity_id.climate_entity_id("climate.kitchen_radiator") |> should.be_ok,
    entity_id.climate_entity_id("climate.hall_radiator") |> should.be_ok,
  ])
}

pub fn parse_invalid_json_test() {
  let json = "not valid json"
  let result = home_config.parse(json)
  result |> should.be_error
}

pub fn parse_invalid_climate_entity_id_test() {
  // Invalid climate entity ID (missing prefix)
  let json =
    "
    {
      \"rooms\": [
        {
          \"name\": \"Room\",
          \"temperatureSensorEntityId\": null,
          \"climateEntityIds\": [\"invalid_entity\"],
          \"schedule\": null
        }
      ],
      \"sleepSwitchId\": \"input_button.goodnight\",
      \"heatingId\": \"climate.main\"
    }
  "

  let result = home_config.parse(json)
  result |> should.be_error
}

pub fn parse_invalid_sensor_entity_id_test() {
  // Invalid sensor entity ID (wrong prefix)
  let json =
    "
    {
      \"rooms\": [
        {
          \"name\": \"Room\",
          \"temperatureSensorEntityId\": \"climate.wrong\",
          \"climateEntityIds\": [\"climate.radiator\"],
          \"schedule\": null
        }
      ],
      \"sleepSwitchId\": \"input_button.goodnight\",
      \"heatingId\": \"climate.main\"
    }
  "

  let result = home_config.parse(json)
  result |> should.be_error
}

// ----------------------------------------------------------------------------
// File loading tests
// ----------------------------------------------------------------------------

const test_config_json = "
{
  \"rooms\": [
    {
      \"name\": \"Test Room\",
      \"temperatureSensorEntityId\": null,
      \"climateEntityIds\": [\"climate.test_radiator\"],
      \"schedule\": null
    }
  ],
  \"sleepSwitchId\": \"input_button.goodnight\",
  \"heatingId\": \"climate.main\"
}
"

pub fn load_from_file_valid_path_test() {
  // Create a temp file with valid config
  let test_path = "/tmp/test_home_config.json"
  let assert Ok(_) = simplifile.write(test_path, test_config_json)

  // Load config from file
  let result = home_config.load_from_file(test_path)

  // Cleanup
  let _ = simplifile.delete(test_path)

  // Verify
  result |> should.be_ok
  let config = result |> should.be_ok
  let assert [room, ..] = config.rooms
  room.name |> should.equal("Test Room")
}

pub fn load_from_file_not_found_test() {
  // Try to load from non-existent file
  let result = home_config.load_from_file("/tmp/nonexistent_config.json")

  result |> should.be_error
  let error = case result {
    Error(err) -> err
    Ok(_) -> panic as "expected error"
  }

  // Should be a FileReadError
  case error {
    home_config.FileReadError(_) -> Nil
    _ -> panic as "expected FileReadError"
  }
}

pub fn load_from_file_invalid_json_test() {
  // Create a temp file with invalid JSON
  let test_path = "/tmp/test_invalid_config.json"
  let assert Ok(_) = simplifile.write(test_path, "not valid json")

  // Load config from file
  let result = home_config.load_from_file(test_path)

  // Cleanup
  let _ = simplifile.delete(test_path)

  // Should be a JsonParseError
  result |> should.be_error
  let error = case result {
    Error(err) -> err
    Ok(_) -> panic as "expected error"
  }

  case error {
    home_config.JsonParseError(_) -> Nil
    _ -> panic as "expected JsonParseError"
  }
}

pub fn load_from_env_test() {
  // Create a temp file with valid config
  let test_path = "/tmp/test_home_config_env.json"
  let assert Ok(_) = simplifile.write(test_path, test_config_json)

  // Set the environment variable
  envoy.set("HOME_CONFIG_PATH", test_path)

  // Load config from env
  let result = home_config.load_from_env()

  // Cleanup
  envoy.unset("HOME_CONFIG_PATH")
  let _ = simplifile.delete(test_path)

  // Verify
  result |> should.be_ok
  let config = result |> should.be_ok
  let assert [room, ..] = config.rooms
  room.name |> should.equal("Test Room")
}

pub fn load_from_env_not_set_test() {
  // Ensure env var is not set
  envoy.unset("HOME_CONFIG_PATH")

  // Load config from env
  let result = home_config.load_from_env()

  // Should be an error
  result |> should.be_error
  let error = case result {
    Error(err) -> err
    Ok(_) -> panic as "expected error"
  }

  // Should be an EnvNotSetError
  case error {
    home_config.EnvNotSetError(_) -> Nil
    _ -> panic as "expected EnvNotSetError"
  }
}
