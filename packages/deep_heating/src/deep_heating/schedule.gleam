import gleam/int
import gleam/list
import gleam/order.{type Order}
import gleam/string
import deep_heating/temperature.{type Temperature}

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

/// Get the scheduled temperature for a given day and time.
/// If the time is before the first entry, uses the last entry from the previous day.
pub fn get_scheduled_temperature(
  schedule: WeekSchedule,
  day: Weekday,
  time: TimeOfDay,
) -> Temperature {
  let day_schedule = get_day_schedule(schedule, day)
  let now_minutes = time_of_day_to_minutes(time)

  // Find the last entry that starts at or before the current time
  let active_entry =
    day_schedule
    |> list.filter(fn(entry) {
      time_of_day_to_minutes(entry.start) <= now_minutes
    })
    |> list.last

  case active_entry {
    Ok(entry) -> entry.target_temperature
    Error(_) -> {
      // Before first entry of day - use last entry from previous day
      let prev_day = previous_day(day)
      let prev_schedule = get_day_schedule(schedule, prev_day)
      case list.last(prev_schedule) {
        Ok(entry) -> entry.target_temperature
        // Fallback: no schedule at all, use first entry of current day
        Error(_) ->
          case list.first(day_schedule) {
            Ok(entry) -> entry.target_temperature
            // This shouldn't happen with a valid schedule
            Error(_) -> temperature.min_room_target
          }
      }
    }
  }
}
