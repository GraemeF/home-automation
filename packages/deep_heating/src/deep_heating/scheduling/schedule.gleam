import deep_heating/temperature.{type Temperature}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{type Order}
import gleam/string

/// Time of day with validated hour (0-23) and minute (0-59).
/// Use time_of_day() smart constructor to create.
pub opaque type TimeOfDay {
  TimeOfDay(hour: Int, minute: Int)
}

/// Create a TimeOfDay, validating hour and minute ranges.
pub fn time_of_day(hour: Int, minute: Int) -> Result(TimeOfDay, String) {
  case hour >= 0 && hour <= 23, minute >= 0 && minute <= 59 {
    True, True -> Ok(TimeOfDay(hour: hour, minute: minute))
    False, _ -> Error("Hour must be 0-23, got: " <> int.to_string(hour))
    _, False -> Error("Minute must be 0-59, got: " <> int.to_string(minute))
  }
}

/// Access the hour component.
pub fn hour(tod: TimeOfDay) -> Int {
  tod.hour
}

/// Access the minute component.
pub fn minute(tod: TimeOfDay) -> Int {
  tod.minute
}

/// Parse TimeOfDay from "HH:MM" string format.
pub fn time_of_day_from_string(s: String) -> Result(TimeOfDay, String) {
  case string.length(s) == 5, string.slice(s, 2, 1) {
    True, ":" -> {
      let hour_str = string.slice(s, 0, 2)
      let minute_str = string.slice(s, 3, 2)
      case int.parse(hour_str), int.parse(minute_str) {
        Ok(h), Ok(m) -> time_of_day(h, m)
        _, _ -> Error("Invalid time format, expected HH:MM: " <> s)
      }
    }
    _, _ -> Error("Invalid time format, expected HH:MM: " <> s)
  }
}

/// Convert TimeOfDay to "HH:MM" string format.
pub fn time_of_day_to_string(tod: TimeOfDay) -> String {
  let h = case tod.hour < 10 {
    True -> "0" <> int.to_string(tod.hour)
    False -> int.to_string(tod.hour)
  }
  let m = case tod.minute < 10 {
    True -> "0" <> int.to_string(tod.minute)
    False -> int.to_string(tod.minute)
  }
  h <> ":" <> m
}

/// Compare two TimeOfDay values.
pub fn time_of_day_compare(a: TimeOfDay, b: TimeOfDay) -> Order {
  case int.compare(a.hour, b.hour) {
    order.Eq -> int.compare(a.minute, b.minute)
    other -> other
  }
}

/// Convert TimeOfDay to minutes since midnight (0-1439).
pub fn time_of_day_to_minutes(tod: TimeOfDay) -> Int {
  tod.hour * 60 + tod.minute
}

/// A schedule entry: a start time and target temperature.
pub type ScheduleEntry {
  ScheduleEntry(start: TimeOfDay, target_temperature: Temperature)
}

/// A day's schedule is a list of entries, ordered by start time.
pub type DaySchedule =
  List(ScheduleEntry)

/// Days of the week.
pub type Weekday {
  Monday
  Tuesday
  Wednesday
  Thursday
  Friday
  Saturday
  Sunday
}

/// A week's heating schedule with entries for each day.
pub type WeekSchedule {
  WeekSchedule(
    monday: DaySchedule,
    tuesday: DaySchedule,
    wednesday: DaySchedule,
    thursday: DaySchedule,
    friday: DaySchedule,
    saturday: DaySchedule,
    sunday: DaySchedule,
  )
}

/// Get the schedule for a specific day.
pub fn get_day_schedule(schedule: WeekSchedule, day: Weekday) -> DaySchedule {
  case day {
    Monday -> schedule.monday
    Tuesday -> schedule.tuesday
    Wednesday -> schedule.wednesday
    Thursday -> schedule.thursday
    Friday -> schedule.friday
    Saturday -> schedule.saturday
    Sunday -> schedule.sunday
  }
}

/// Get the previous day of the week.
pub fn previous_day(day: Weekday) -> Weekday {
  case day {
    Monday -> Sunday
    Tuesday -> Monday
    Wednesday -> Tuesday
    Thursday -> Wednesday
    Friday -> Thursday
    Saturday -> Friday
    Sunday -> Saturday
  }
}

/// Get the scheduled temperature for a given day and time using temperature ramping.
///
/// The ramping algorithm pre-heats before scheduled temperature increases:
/// - For each schedule entry, calculate: effective = target - 0.5 × hours_until
/// - Return the maximum of all effective temperatures
///
/// This creates gradual temperature transitions: as you approach an entry's
/// start time, its contribution increases by 0.5°C per hour.
pub fn get_scheduled_temperature(
  schedule: WeekSchedule,
  day: Weekday,
  time: TimeOfDay,
) -> Temperature {
  let day_schedule = get_day_schedule(schedule, day)
  let now_minutes = time_of_day_to_minutes(time)

  // Find the active entry: last entry with start <= now, or previous day's last
  let active_entry_opt = find_active_entry(schedule, day, now_minutes)

  // Calculate effective temperatures for all entries
  let effective_temps =
    day_schedule
    |> list.map(fn(entry) {
      let entry_minutes = time_of_day_to_minutes(entry.start)
      let hours_until =
        calculate_hours_until(
          entry_minutes,
          now_minutes,
          is_active_entry(entry, active_entry_opt),
        )
      calculate_effective_temp(entry.target_temperature, hours_until)
    })

  // Include the active entry if it's from previous day
  let all_effective_temps = case active_entry_opt {
    Some(active) -> {
      // Check if active entry is from today's schedule
      let is_from_today =
        list.any(day_schedule, fn(e) {
          time_of_day_to_minutes(e.start)
          == time_of_day_to_minutes(active.start)
          && temperature.eq(e.target_temperature, active.target_temperature)
        })
      case is_from_today {
        True -> effective_temps
        False -> {
          // Active entry is from previous day, add it with hours_until = 0
          let active_effective =
            calculate_effective_temp(active.target_temperature, 0.0)
          [active_effective, ..effective_temps]
        }
      }
    }
    None -> effective_temps
  }

  // Return maximum effective temperature
  case list.reduce(all_effective_temps, temperature.max) {
    Ok(max_temp) -> max_temp
    Error(_) -> temperature.min_room_target
  }
}

/// Find the active schedule entry (last entry with start <= now).
/// If current time is before first entry of day, returns previous day's last entry.
fn find_active_entry(
  schedule: WeekSchedule,
  day: Weekday,
  now_minutes: Int,
) -> Option(ScheduleEntry) {
  let day_schedule = get_day_schedule(schedule, day)

  // Find last entry in today's schedule that started before or at now
  let today_active =
    day_schedule
    |> list.filter(fn(entry) {
      time_of_day_to_minutes(entry.start) <= now_minutes
    })
    |> list.last

  case today_active {
    Ok(entry) -> Some(entry)
    Error(_) -> {
      // Before first entry of day - use last entry from previous day
      let prev_day = previous_day(day)
      let prev_schedule = get_day_schedule(schedule, prev_day)
      case list.last(prev_schedule) {
        Ok(entry) -> Some(entry)
        Error(_) -> None
      }
    }
  }
}

/// Check if an entry matches the active entry.
fn is_active_entry(
  entry: ScheduleEntry,
  active_opt: Option(ScheduleEntry),
) -> Bool {
  case active_opt {
    Some(active) ->
      time_of_day_to_minutes(entry.start)
      == time_of_day_to_minutes(active.start)
      && temperature.eq(entry.target_temperature, active.target_temperature)
    None -> False
  }
}

/// Calculate hours until an entry activates.
/// - Active entry: 0
/// - Future entry (entry_minutes > now_minutes): positive hours
/// - Past non-active entry: wraps to tomorrow (24+ hours)
fn calculate_hours_until(
  entry_minutes: Int,
  now_minutes: Int,
  is_active: Bool,
) -> Float {
  case is_active {
    True -> 0.0
    False -> {
      let diff = entry_minutes - now_minutes
      case diff > 0 {
        True -> int.to_float(diff) /. 60.0
        False -> int.to_float(24 * 60 + diff) /. 60.0
      }
    }
  }
}

/// Calculate effective temperature with ramping.
/// effective = target - 0.5 × hours_until
/// Result is rounded to 0.1°C.
fn calculate_effective_temp(
  target: Temperature,
  hours_until: Float,
) -> Temperature {
  let target_value = temperature.unwrap(target)
  let effective = target_value -. 0.5 *. hours_until
  // Round to 0.1°C (same as TypeScript: Math.round(x * 10) / 10)
  let rounded = int.to_float(float.round(effective *. 10.0)) /. 10.0
  temperature.temperature(rounded)
}
