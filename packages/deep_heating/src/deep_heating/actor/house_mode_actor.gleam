//// HouseModeActor - singleton actor tracking house-wide mode (Auto/Sleeping).
////
//// Responsibilities:
//// - Track current house mode (Auto/Sleeping)
//// - Accept room actor registrations
//// - Broadcast mode changes to all registered room actors
//// - Automatically evaluate mode based on time:
////   - Before 3am: Sleeping
////   - After 3am: Auto (unless button pressed after 8pm same day)
////   - Button pressed after 8pm: Sleeping (until 3am next day)

import deep_heating/actor/room_actor
import deep_heating/mode.{type HouseMode, HouseModeAuto, HouseModeSleeping}
import gleam/erlang/process.{type Name, type Subject}
import gleam/list
import gleam/otp/actor
import gleam/otp/supervision

/// LocalDateTime represents a date and time (year, month, day, hour, minute, second)
pub opaque type LocalDateTime {
  LocalDateTime(
    year: Int,
    month: Int,
    day: Int,
    hour: Int,
    minute: Int,
    second: Int,
  )
}

/// Create a LocalDateTime from components
pub fn local_datetime(
  year: Int,
  month: Int,
  day: Int,
  hour: Int,
  minute: Int,
  second: Int,
) -> LocalDateTime {
  LocalDateTime(year, month, day, hour, minute, second)
}

/// Get the hour component of a LocalDateTime
pub fn datetime_hour(dt: LocalDateTime) -> Int {
  dt.hour
}

/// Get the date components (year, month, day) for same-day comparison
fn datetime_date(dt: LocalDateTime) -> #(Int, Int, Int) {
  #(dt.year, dt.month, dt.day)
}

/// Check if two datetimes are on the same day
fn same_day(a: LocalDateTime, b: LocalDateTime) -> Bool {
  datetime_date(a) == datetime_date(b)
}

/// Get current local time from Erlang calendar (production use)
@external(erlang, "calendar", "local_time")
fn erlang_local_time() -> #(#(Int, Int, Int), #(Int, Int, Int))

/// Get current time using Erlang's calendar:local_time()
pub fn now() -> LocalDateTime {
  let #(#(year, month, day), #(hour, minute, second)) = erlang_local_time()
  LocalDateTime(year, month, day, hour, minute, second)
}

/// Messages handled by the HouseModeActor
pub type Message {
  /// Get the current house mode
  GetMode(reply_to: Subject(HouseMode))
  /// Set the house to sleeping mode (goodnight button pressed)
  SleepButtonPressed
  /// Wake up the house (timer or manual)
  WakeUp
  /// Register a room actor to receive mode change broadcasts
  RegisterRoomActor(room_actor: Subject(room_actor.Message))
  /// Re-evaluate mode based on current time (called by internal timer)
  ReEvaluateMode
}

/// Type alias for time provider function
pub type TimeProvider =
  fn() -> LocalDateTime

/// Internal state of the HouseModeActor
type State {
  State(
    mode: HouseMode,
    room_actors: List(Subject(room_actor.Message)),
    get_now: TimeProvider,
    last_button_press: Result(LocalDateTime, Nil),
    self_subject: Result(Subject(Message), Nil),
  )
}

/// Start the HouseModeActor without name registration (for testing)
pub fn start_link() -> Result(Subject(Message), actor.StartError) {
  start_with_time_provider(now)
}

/// Start the HouseModeActor with a custom time provider (for testing)
pub fn start_with_time_provider(
  get_now: TimeProvider,
) -> Result(Subject(Message), actor.StartError) {
  // Evaluate initial mode based on current time
  let current_time = get_now()
  let initial_mode = evaluate_mode(current_time, Error(Nil))

  let initial_state =
    State(
      mode: initial_mode,
      room_actors: [],
      get_now: get_now,
      last_button_press: Error(Nil),
      self_subject: Error(Nil),
    )

  actor.new(initial_state)
  |> actor.on_message(handle_message)
  |> actor.start
  |> extract_subject
}

/// Start the HouseModeActor and register it with the given name
pub fn start(
  name: Name(Message),
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  // Evaluate initial mode based on current time
  let current_time = now()
  let initial_mode = evaluate_mode(current_time, Error(Nil))

  let initial_state =
    State(
      mode: initial_mode,
      room_actors: [],
      get_now: now,
      last_button_press: Error(Nil),
      self_subject: Error(Nil),
    )

  actor.new(initial_state)
  |> actor.on_message(handle_message)
  |> actor.start
  |> register_with_name(name)
}

/// Create a child specification for supervision
pub fn child_spec(
  name: Name(Message),
) -> supervision.ChildSpecification(Subject(Message)) {
  supervision.worker(fn() { start(name) })
}

/// Evaluate what mode the house should be in based on current time and button press
/// Logic from TypeScript:
/// 1. If button pressed today AND after 8pm (hour > 20) → Sleeping
/// 2. Else if current hour < 3 → Sleeping
/// 3. Else → Auto
fn evaluate_mode(
  current_time: LocalDateTime,
  last_button_press: Result(LocalDateTime, Nil),
) -> HouseMode {
  let current_hour = datetime_hour(current_time)

  case last_button_press {
    Ok(button_time) -> {
      // Check if button was pressed today and after 8pm
      let button_hour = datetime_hour(button_time)
      case same_day(button_time, current_time) && button_hour > 20 {
        True -> HouseModeSleeping
        False -> {
          // Button was pressed but not valid (wrong day or before 8pm)
          // Fall through to time-based logic
          case current_hour < 3 {
            True -> HouseModeSleeping
            False -> HouseModeAuto
          }
        }
      }
    }
    Error(_) -> {
      // No button pressed - just use time-based logic
      case current_hour < 3 {
        True -> HouseModeSleeping
        False -> HouseModeAuto
      }
    }
  }
}

fn handle_message(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    GetMode(reply_to) -> {
      process.send(reply_to, state.mode)
      actor.continue(state)
    }
    SleepButtonPressed -> {
      // Record the button press time
      let current_time = state.get_now()
      let current_hour = datetime_hour(current_time)

      // Only accept button press if after 8pm (hour > 20)
      case current_hour > 20 {
        True -> {
          // Valid button press - update state and mode
          let new_state =
            State(
              ..state,
              last_button_press: Ok(current_time),
              mode: HouseModeSleeping,
            )
          broadcast_mode_change(new_state.room_actors, HouseModeSleeping)
          actor.continue(new_state)
        }
        False -> {
          // Button pressed before 8pm - record it but don't change mode yet
          // (mode will be evaluated based on time)
          let new_state = State(..state, last_button_press: Ok(current_time))
          // Re-evaluate mode (in case it's before 3am)
          let new_mode =
            evaluate_mode(current_time, new_state.last_button_press)
          case new_mode != state.mode {
            True -> {
              broadcast_mode_change(new_state.room_actors, new_mode)
              actor.continue(State(..new_state, mode: new_mode))
            }
            False -> actor.continue(new_state)
          }
        }
      }
    }
    WakeUp -> {
      // Clear button press and set to Auto
      let new_state =
        State(..state, last_button_press: Error(Nil), mode: HouseModeAuto)
      broadcast_mode_change(new_state.room_actors, HouseModeAuto)
      actor.continue(new_state)
    }
    RegisterRoomActor(room_actor) -> {
      actor.continue(
        State(..state, room_actors: [room_actor, ..state.room_actors]),
      )
    }
    ReEvaluateMode -> {
      // Re-evaluate mode based on current time
      let current_time = state.get_now()
      let new_mode = evaluate_mode(current_time, state.last_button_press)
      case new_mode != state.mode {
        True -> {
          broadcast_mode_change(state.room_actors, new_mode)
          actor.continue(State(..state, mode: new_mode))
        }
        False -> actor.continue(state)
      }
    }
  }
}

fn broadcast_mode_change(
  room_actors: List(Subject(room_actor.Message)),
  new_mode: HouseMode,
) -> Nil {
  list.each(room_actors, fn(ra) {
    process.send(ra, room_actor.HouseModeChanged(new_mode))
  })
}

fn extract_subject(
  result: Result(actor.Started(Subject(Message)), actor.StartError),
) -> Result(Subject(Message), actor.StartError) {
  case result {
    Ok(started) -> Ok(started.data)
    Error(e) -> Error(e)
  }
}

fn register_with_name(
  result: Result(actor.Started(Subject(Message)), actor.StartError),
  name: Name(Message),
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  case result {
    Ok(started) -> {
      let _ = process.register(started.pid, name)
      Ok(started)
    }
    Error(e) -> Error(e)
  }
}
