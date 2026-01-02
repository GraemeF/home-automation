import gleam/order
import gleeunit/should
import deep_heating/temperature.{temperature, unwrap}
import deep_heating/schedule.{
  time_of_day, time_of_day_from_string, time_of_day_to_string,
  time_of_day_compare, time_of_day_to_minutes, hour, minute,
  ScheduleEntry,
  WeekSchedule,
  Monday, Tuesday, Saturday,
  get_scheduled_temperature,
}

// TimeOfDay construction tests

pub fn time_of_day_valid_test() {
  let assert Ok(tod) = time_of_day(9, 30)
  tod |> hour |> should.equal(9)
  tod |> minute |> should.equal(30)
}

pub fn time_of_day_midnight_test() {
  let assert Ok(tod) = time_of_day(0, 0)
  tod |> hour |> should.equal(0)
  tod |> minute |> should.equal(0)
}

pub fn time_of_day_end_of_day_test() {
  let assert Ok(tod) = time_of_day(23, 59)
  tod |> hour |> should.equal(23)
  tod |> minute |> should.equal(59)
}

pub fn time_of_day_invalid_hour_test() {
  time_of_day(24, 0) |> should.be_error
}

pub fn time_of_day_invalid_negative_hour_test() {
  time_of_day(-1, 0) |> should.be_error
}

pub fn time_of_day_invalid_minute_test() {
  time_of_day(12, 60) |> should.be_error
}

pub fn time_of_day_invalid_negative_minute_test() {
  time_of_day(12, -1) |> should.be_error
}

// TimeOfDay string parsing tests

pub fn time_of_day_from_string_valid_test() {
  let assert Ok(tod) = time_of_day_from_string("09:30")
  tod |> hour |> should.equal(9)
  tod |> minute |> should.equal(30)
}

pub fn time_of_day_from_string_midnight_test() {
  let assert Ok(tod) = time_of_day_from_string("00:00")
  tod |> hour |> should.equal(0)
  tod |> minute |> should.equal(0)
}

pub fn time_of_day_from_string_afternoon_test() {
  let assert Ok(tod) = time_of_day_from_string("14:45")
  tod |> hour |> should.equal(14)
  tod |> minute |> should.equal(45)
}

pub fn time_of_day_from_string_invalid_format_test() {
  time_of_day_from_string("9:30") |> should.be_error
}

pub fn time_of_day_from_string_invalid_separator_test() {
  time_of_day_from_string("09-30") |> should.be_error
}

pub fn time_of_day_from_string_invalid_chars_test() {
  time_of_day_from_string("ab:cd") |> should.be_error
}

// TimeOfDay to string tests

pub fn time_of_day_to_string_test() {
  let assert Ok(tod) = time_of_day(9, 30)
  tod |> time_of_day_to_string |> should.equal("09:30")
}

pub fn time_of_day_to_string_midnight_test() {
  let assert Ok(tod) = time_of_day(0, 0)
  tod |> time_of_day_to_string |> should.equal("00:00")
}

pub fn time_of_day_to_string_afternoon_test() {
  let assert Ok(tod) = time_of_day(14, 5)
  tod |> time_of_day_to_string |> should.equal("14:05")
}

// TimeOfDay comparison tests

pub fn time_of_day_compare_equal_test() {
  let assert Ok(a) = time_of_day(9, 30)
  let assert Ok(b) = time_of_day(9, 30)
  time_of_day_compare(a, b) |> should.equal(order.Eq)
}

pub fn time_of_day_compare_less_hour_test() {
  let assert Ok(a) = time_of_day(8, 30)
  let assert Ok(b) = time_of_day(9, 30)
  time_of_day_compare(a, b) |> should.equal(order.Lt)
}

pub fn time_of_day_compare_greater_hour_test() {
  let assert Ok(a) = time_of_day(10, 30)
  let assert Ok(b) = time_of_day(9, 30)
  time_of_day_compare(a, b) |> should.equal(order.Gt)
}

pub fn time_of_day_compare_less_minute_test() {
  let assert Ok(a) = time_of_day(9, 15)
  let assert Ok(b) = time_of_day(9, 30)
  time_of_day_compare(a, b) |> should.equal(order.Lt)
}

pub fn time_of_day_compare_greater_minute_test() {
  let assert Ok(a) = time_of_day(9, 45)
  let assert Ok(b) = time_of_day(9, 30)
  time_of_day_compare(a, b) |> should.equal(order.Gt)
}

// TimeOfDay to minutes tests

pub fn time_of_day_to_minutes_midnight_test() {
  let assert Ok(tod) = time_of_day(0, 0)
  tod |> time_of_day_to_minutes |> should.equal(0)
}

pub fn time_of_day_to_minutes_test() {
  let assert Ok(tod) = time_of_day(9, 30)
  tod |> time_of_day_to_minutes |> should.equal(570)
}

pub fn time_of_day_to_minutes_end_of_day_test() {
  let assert Ok(tod) = time_of_day(23, 59)
  tod |> time_of_day_to_minutes |> should.equal(1439)
}

// ScheduleEntry tests

pub fn schedule_entry_construction_test() {
  let assert Ok(start) = time_of_day(7, 0)
  let entry = ScheduleEntry(start: start, target_temperature: temperature(20.0))
  entry.target_temperature |> unwrap |> should.equal(20.0)
}

// WeekSchedule tests

pub fn week_schedule_construction_test() {
  let assert Ok(morning) = time_of_day(7, 0)
  let assert Ok(night) = time_of_day(22, 0)

  let day = [
    ScheduleEntry(start: morning, target_temperature: temperature(20.0)),
    ScheduleEntry(start: night, target_temperature: temperature(16.0)),
  ]

  let schedule = WeekSchedule(
    monday: day,
    tuesday: day,
    wednesday: day,
    thursday: day,
    friday: day,
    saturday: day,
    sunday: day,
  )

  let assert [first, ..] = schedule.monday
  first.target_temperature |> unwrap |> should.equal(20.0)
}

// get_scheduled_temperature tests

pub fn get_scheduled_temperature_single_entry_test() {
  let assert Ok(start) = time_of_day(0, 0)
  let day = [ScheduleEntry(start: start, target_temperature: temperature(18.0))]
  let schedule = WeekSchedule(
    monday: day, tuesday: day, wednesday: day, thursday: day,
    friday: day, saturday: day, sunday: day,
  )

  let assert Ok(now) = time_of_day(12, 0)
  get_scheduled_temperature(schedule, Monday, now)
  |> unwrap
  |> should.equal(18.0)
}

pub fn get_scheduled_temperature_morning_entry_test() {
  let assert Ok(morning) = time_of_day(7, 0)
  let assert Ok(evening) = time_of_day(18, 0)
  let assert Ok(night) = time_of_day(22, 0)

  let day = [
    ScheduleEntry(start: morning, target_temperature: temperature(20.0)),
    ScheduleEntry(start: evening, target_temperature: temperature(21.0)),
    ScheduleEntry(start: night, target_temperature: temperature(16.0)),
  ]
  let schedule = WeekSchedule(
    monday: day, tuesday: day, wednesday: day, thursday: day,
    friday: day, saturday: day, sunday: day,
  )

  // At 10:00, should be in morning slot (20.0)
  let assert Ok(now) = time_of_day(10, 0)
  get_scheduled_temperature(schedule, Monday, now)
  |> unwrap
  |> should.equal(20.0)
}

pub fn get_scheduled_temperature_evening_entry_test() {
  let assert Ok(morning) = time_of_day(7, 0)
  let assert Ok(evening) = time_of_day(18, 0)
  let assert Ok(night) = time_of_day(22, 0)

  let day = [
    ScheduleEntry(start: morning, target_temperature: temperature(20.0)),
    ScheduleEntry(start: evening, target_temperature: temperature(21.0)),
    ScheduleEntry(start: night, target_temperature: temperature(16.0)),
  ]
  let schedule = WeekSchedule(
    monday: day, tuesday: day, wednesday: day, thursday: day,
    friday: day, saturday: day, sunday: day,
  )

  // At 19:00, should be in evening slot (21.0)
  let assert Ok(now) = time_of_day(19, 0)
  get_scheduled_temperature(schedule, Monday, now)
  |> unwrap
  |> should.equal(21.0)
}

pub fn get_scheduled_temperature_night_entry_test() {
  let assert Ok(morning) = time_of_day(7, 0)
  let assert Ok(evening) = time_of_day(18, 0)
  let assert Ok(night) = time_of_day(22, 0)

  let day = [
    ScheduleEntry(start: morning, target_temperature: temperature(20.0)),
    ScheduleEntry(start: evening, target_temperature: temperature(21.0)),
    ScheduleEntry(start: night, target_temperature: temperature(16.0)),
  ]
  let schedule = WeekSchedule(
    monday: day, tuesday: day, wednesday: day, thursday: day,
    friday: day, saturday: day, sunday: day,
  )

  // At 23:00, should be in night slot (16.0)
  let assert Ok(now) = time_of_day(23, 0)
  get_scheduled_temperature(schedule, Monday, now)
  |> unwrap
  |> should.equal(16.0)
}

pub fn get_scheduled_temperature_before_first_entry_test() {
  // If current time is before the first entry, use last entry from previous day
  let assert Ok(morning) = time_of_day(7, 0)
  let assert Ok(night) = time_of_day(22, 0)

  let day = [
    ScheduleEntry(start: morning, target_temperature: temperature(20.0)),
    ScheduleEntry(start: night, target_temperature: temperature(16.0)),
  ]
  let schedule = WeekSchedule(
    monday: day, tuesday: day, wednesday: day, thursday: day,
    friday: day, saturday: day, sunday: day,
  )

  // At 05:00 on Tuesday (before 07:00), should use Monday night's temp (16.0)
  let assert Ok(now) = time_of_day(5, 0)
  get_scheduled_temperature(schedule, Tuesday, now)
  |> unwrap
  |> should.equal(16.0)
}

pub fn get_scheduled_temperature_exactly_at_entry_test() {
  let assert Ok(morning) = time_of_day(7, 0)
  let assert Ok(evening) = time_of_day(18, 0)

  let day = [
    ScheduleEntry(start: morning, target_temperature: temperature(20.0)),
    ScheduleEntry(start: evening, target_temperature: temperature(21.0)),
  ]
  let schedule = WeekSchedule(
    monday: day, tuesday: day, wednesday: day, thursday: day,
    friday: day, saturday: day, sunday: day,
  )

  // Exactly at 18:00, should be evening temp
  let assert Ok(now) = time_of_day(18, 0)
  get_scheduled_temperature(schedule, Monday, now)
  |> unwrap
  |> should.equal(21.0)
}

pub fn get_scheduled_temperature_different_weekend_test() {
  let assert Ok(morning) = time_of_day(7, 0)
  let assert Ok(weekend_morning) = time_of_day(9, 0)

  let weekday = [
    ScheduleEntry(start: morning, target_temperature: temperature(20.0)),
  ]
  let weekend = [
    ScheduleEntry(start: weekend_morning, target_temperature: temperature(19.0)),
  ]

  let schedule = WeekSchedule(
    monday: weekday, tuesday: weekday, wednesday: weekday,
    thursday: weekday, friday: weekday,
    saturday: weekend, sunday: weekend,
  )

  let assert Ok(now) = time_of_day(10, 0)

  // Weekday at 10:00
  get_scheduled_temperature(schedule, Monday, now)
  |> unwrap
  |> should.equal(20.0)

  // Weekend at 10:00
  get_scheduled_temperature(schedule, Saturday, now)
  |> unwrap
  |> should.equal(19.0)
}
