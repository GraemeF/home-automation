// Home configuration parsing
// Parses the home.json configuration file that defines rooms, TRVs, and schedules

import deep_heating/entity_id.{
  type ClimateEntityId, type GoodnightEntityId, type SensorEntityId,
}
import deep_heating/schedule.{
  type DaySchedule, type WeekSchedule, ScheduleEntry, WeekSchedule,
}
import deep_heating/temperature
import gleam/dict.{type Dict}
import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// Configuration for a single room
pub type RoomConfig {
  RoomConfig(
    name: String,
    temperature_sensor_entity_id: Option(SensorEntityId),
    climate_entity_ids: List(ClimateEntityId),
    schedule: Option(WeekSchedule),
  )
}

/// Top-level home configuration
pub type HomeConfig {
  HomeConfig(
    rooms: List(RoomConfig),
    sleep_switch_id: GoodnightEntityId,
    heating_id: ClimateEntityId,
  )
}

/// Errors that can occur when parsing configuration
pub type ConfigError {
  JsonParseError(message: String)
  ValidationError(message: String)
}

/// Parse a JSON string into HomeConfig
pub fn parse(json_string: String) -> Result(HomeConfig, ConfigError) {
  // First, decode the raw structure
  json.parse(json_string, raw_config_decoder())
  |> result.map_error(fn(err) {
    JsonParseError("Failed to parse config JSON: " <> string.inspect(err))
  })
  |> result.try(convert_raw_to_config)
}

// -----------------------------------------------------------------------------
// Raw Types (for intermediate parsing before validation)
// -----------------------------------------------------------------------------

type RawRoomConfig {
  RawRoomConfig(
    name: String,
    temperature_sensor_entity_id: Option(String),
    climate_entity_ids: List(String),
    schedule: Option(RawWeekSchedule),
  )
}

type RawWeekSchedule {
  RawWeekSchedule(
    monday: Dict(String, Float),
    tuesday: Dict(String, Float),
    wednesday: Dict(String, Float),
    thursday: Dict(String, Float),
    friday: Dict(String, Float),
    saturday: Dict(String, Float),
    sunday: Dict(String, Float),
  )
}

type RawConfig {
  RawConfig(
    rooms: List(RawRoomConfig),
    sleep_switch_id: String,
    heating_id: String,
  )
}

// -----------------------------------------------------------------------------
// Decoders
// -----------------------------------------------------------------------------

fn raw_config_decoder() -> Decoder(RawConfig) {
  decode.field("rooms", decode.list(raw_room_decoder()), fn(rooms) {
    decode.field("sleepSwitchId", decode.string, fn(sleep_switch_id) {
      decode.field("heatingId", decode.string, fn(heating_id) {
        decode.success(RawConfig(
          rooms: rooms,
          sleep_switch_id: sleep_switch_id,
          heating_id: heating_id,
        ))
      })
    })
  })
}

fn raw_room_decoder() -> Decoder(RawRoomConfig) {
  decode.field("name", decode.string, fn(name) {
    decode.field(
      "temperatureSensorEntityId",
      decode.optional(decode.string),
      fn(sensor_id) {
        decode.field(
          "climateEntityIds",
          decode.list(decode.string),
          fn(climate_ids) {
            decode.field(
              "schedule",
              decode.optional(raw_schedule_decoder()),
              fn(sched) {
                decode.success(RawRoomConfig(
                  name: name,
                  temperature_sensor_entity_id: sensor_id,
                  climate_entity_ids: climate_ids,
                  schedule: sched,
                ))
              },
            )
          },
        )
      },
    )
  })
}

fn raw_schedule_decoder() -> Decoder(RawWeekSchedule) {
  decode.field("monday", day_schedule_decoder(), fn(monday) {
    decode.field("tuesday", day_schedule_decoder(), fn(tuesday) {
      decode.field("wednesday", day_schedule_decoder(), fn(wednesday) {
        decode.field("thursday", day_schedule_decoder(), fn(thursday) {
          decode.field("friday", day_schedule_decoder(), fn(friday) {
            decode.field("saturday", day_schedule_decoder(), fn(saturday) {
              decode.field("sunday", day_schedule_decoder(), fn(sunday) {
                decode.success(RawWeekSchedule(
                  monday: monday,
                  tuesday: tuesday,
                  wednesday: wednesday,
                  thursday: thursday,
                  friday: friday,
                  saturday: saturday,
                  sunday: sunday,
                ))
              })
            })
          })
        })
      })
    })
  })
}

fn day_schedule_decoder() -> Decoder(Dict(String, Float)) {
  // Decode a dict of time strings to temperature floats
  // The JSON looks like: { "07:00": 20.0, "22:00": 16.0 }
  decode.dict(decode.string, number_decoder())
}

fn number_decoder() -> Decoder(Float) {
  // JSON numbers can be int or float, we want them as Float
  decode.one_of(decode.float, [
    decode.then(decode.int, fn(i) { decode.success(int.to_float(i)) }),
  ])
}

// -----------------------------------------------------------------------------
// Conversion from Raw to Validated
// -----------------------------------------------------------------------------

fn convert_raw_to_config(raw: RawConfig) -> Result(HomeConfig, ConfigError) {
  // Validate sleep switch ID
  use sleep_switch_id <- result.try(
    entity_id.goodnight_entity_id(raw.sleep_switch_id)
    |> result.map_error(fn(err) {
      ValidationError("Invalid sleepSwitchId: " <> err)
    }),
  )

  // Validate heating ID
  use heating_id <- result.try(
    entity_id.climate_entity_id(raw.heating_id)
    |> result.map_error(fn(err) {
      ValidationError("Invalid heatingId: " <> err)
    }),
  )

  // Convert all rooms
  use rooms <- result.try(
    raw.rooms
    |> list.try_map(convert_raw_room),
  )

  Ok(HomeConfig(
    rooms: rooms,
    sleep_switch_id: sleep_switch_id,
    heating_id: heating_id,
  ))
}

fn convert_raw_room(raw: RawRoomConfig) -> Result(RoomConfig, ConfigError) {
  // Validate optional sensor ID
  use sensor_id <- result.try(case raw.temperature_sensor_entity_id {
    None -> Ok(None)
    Some(id) ->
      entity_id.sensor_entity_id(id)
      |> result.map(Some)
      |> result.map_error(fn(err) {
        ValidationError(
          "Invalid temperatureSensorEntityId in room '"
          <> raw.name
          <> "': "
          <> err,
        )
      })
  })

  // Validate climate entity IDs
  use climate_ids <- result.try(
    raw.climate_entity_ids
    |> list.try_map(fn(id) {
      entity_id.climate_entity_id(id)
      |> result.map_error(fn(err) {
        ValidationError(
          "Invalid climateEntityId in room '" <> raw.name <> "': " <> err,
        )
      })
    }),
  )

  // Convert optional schedule
  use sched <- result.try(case raw.schedule {
    None -> Ok(None)
    Some(raw_sched) ->
      convert_raw_schedule(raw_sched, raw.name)
      |> result.map(Some)
  })

  Ok(RoomConfig(
    name: raw.name,
    temperature_sensor_entity_id: sensor_id,
    climate_entity_ids: climate_ids,
    schedule: sched,
  ))
}

fn convert_raw_schedule(
  raw: RawWeekSchedule,
  room_name: String,
) -> Result(WeekSchedule, ConfigError) {
  use monday <- result.try(convert_day_schedule(raw.monday, room_name, "monday"))
  use tuesday <- result.try(convert_day_schedule(
    raw.tuesday,
    room_name,
    "tuesday",
  ))
  use wednesday <- result.try(convert_day_schedule(
    raw.wednesday,
    room_name,
    "wednesday",
  ))
  use thursday <- result.try(convert_day_schedule(
    raw.thursday,
    room_name,
    "thursday",
  ))
  use friday <- result.try(convert_day_schedule(raw.friday, room_name, "friday"))
  use saturday <- result.try(convert_day_schedule(
    raw.saturday,
    room_name,
    "saturday",
  ))
  use sunday <- result.try(convert_day_schedule(raw.sunday, room_name, "sunday"))

  Ok(WeekSchedule(
    monday: monday,
    tuesday: tuesday,
    wednesday: wednesday,
    thursday: thursday,
    friday: friday,
    saturday: saturday,
    sunday: sunday,
  ))
}

fn convert_day_schedule(
  raw: Dict(String, Float),
  room_name: String,
  day_name: String,
) -> Result(DaySchedule, ConfigError) {
  raw
  |> dict.to_list
  |> list.try_map(fn(pair) {
    let #(time_str, temp_value) = pair
    // Parse time
    use time <- result.try(
      schedule.time_of_day_from_string(time_str)
      |> result.map_error(fn(err) {
        ValidationError(
          "Invalid time in room '"
          <> room_name
          <> "' schedule for "
          <> day_name
          <> ": "
          <> err,
        )
      }),
    )
    let temp = temperature.temperature(temp_value)
    Ok(ScheduleEntry(start: time, target_temperature: temp))
  })
  |> result.map(fn(entries) {
    // Sort by time
    list.sort(entries, fn(a, b) {
      schedule.time_of_day_compare(a.start, b.start)
    })
  })
}
