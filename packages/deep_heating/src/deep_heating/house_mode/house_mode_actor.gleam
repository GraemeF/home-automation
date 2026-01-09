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

import deep_heating/log
import deep_heating/mode.{type HouseMode, HouseModeAuto, HouseModeSleeping}
import deep_heating/rooms/room_actor
import deep_heating/timer.{type SendAfter, type TimerHandle}
import gleam/erlang/process.{type Name, type Subject}
import gleam/int
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
  /// Gracefully stop the actor, cancelling any pending timer
  Shutdown
}

/// Type alias for time provider function
pub type TimeProvider =
  fn() -> LocalDateTime

/// Default timer interval in milliseconds (63 seconds)
pub const default_timer_interval_ms: Int = 63_000

/// Internal state of the HouseModeActor
type State {
  State(
    mode: HouseMode,
    room_actors: List(Subject(room_actor.Message)),
    get_now: TimeProvider,
    last_button_press: Result(LocalDateTime, Nil),
    self_subject: Result(Subject(Message), Nil),
    timer_interval_ms: Int,
    send_after: SendAfter(Message),
    /// Handle to the current timer (for cancellation on shutdown)
    timer_handle: Result(TimerHandle, Nil),
  )
}

/// Start the HouseModeActor without name registration (for testing)
pub fn start_link() -> Result(Subject(Message), actor.StartError) {
  start_with_time_provider(now)
}

/// Start the HouseModeActor with a custom time provider (for testing)
/// Uses the default 63-second timer interval
pub fn start_with_time_provider(
  get_now: TimeProvider,
) -> Result(Subject(Message), actor.StartError) {
  start_with_timer_interval(get_now, default_timer_interval_ms)
}

/// Start the HouseModeActor with custom time provider and timer interval
/// Timer interval is in milliseconds (use 0 to disable timer)
pub fn start_with_timer_interval(
  get_now: TimeProvider,
  timer_interval_ms: Int,
) -> Result(Subject(Message), actor.StartError) {
  start_with_options(
    get_now: get_now,
    timer_interval_ms: timer_interval_ms,
    send_after: timer.real_send_after,
  )
}

/// Start the HouseModeActor with all options (for testing)
/// Allows injection of send_after for deterministic timer testing
pub fn start_with_options(
  get_now get_now: TimeProvider,
  timer_interval_ms timer_interval_ms: Int,
  send_after send_after: SendAfter(Message),
) -> Result(Subject(Message), actor.StartError) {
  // Evaluate initial mode based on current time
  let current_time = get_now()
  let initial_mode = evaluate_mode(current_time, Error(Nil))

  actor.new_with_initialiser(1000, fn(self_subject) {
    // Schedule initial timer if interval > 0 and capture handle
    let initial_timer_handle = case timer_interval_ms > 0 {
      True -> {
        let handle = send_after(self_subject, timer_interval_ms, ReEvaluateMode)
        Ok(handle)
      }
      False -> Error(Nil)
    }

    let initial_state =
      State(
        mode: initial_mode,
        room_actors: [],
        get_now: get_now,
        last_button_press: Error(Nil),
        self_subject: Ok(self_subject),
        timer_interval_ms: timer_interval_ms,
        send_after: send_after,
        timer_handle: initial_timer_handle,
      )

    actor.initialised(initial_state)
    |> actor.returning(self_subject)
    |> Ok
  })
  |> actor.on_message(handle_message)
  |> actor.start
  |> extract_subject
}

/// Start the HouseModeActor and register it with the given name
pub fn start(
  name: Name(Message),
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  start_named_with_time_provider(name, now)
}

/// Start the HouseModeActor with a custom time provider and register with given name
pub fn start_named_with_time_provider(
  name: Name(Message),
  get_now: TimeProvider,
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  start_named_with_options(
    name: name,
    get_now: get_now,
    timer_interval_ms: default_timer_interval_ms,
    send_after: timer.real_send_after,
  )
}

/// Start the HouseModeActor with all options and register with given name (for testing)
pub fn start_named_with_options(
  name name: Name(Message),
  get_now get_now: TimeProvider,
  timer_interval_ms timer_interval_ms: Int,
  send_after send_after: SendAfter(Message),
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  // Evaluate initial mode based on current time
  let current_time = get_now()
  let initial_mode = evaluate_mode(current_time, Error(Nil))

  actor.new_with_initialiser(1000, fn(self_subject) {
    // Schedule initial timer if interval > 0 and capture handle
    let initial_timer_handle = case timer_interval_ms > 0 {
      True -> {
        let handle = send_after(self_subject, timer_interval_ms, ReEvaluateMode)
        Ok(handle)
      }
      False -> Error(Nil)
    }

    let initial_state =
      State(
        mode: initial_mode,
        room_actors: [],
        get_now: get_now,
        last_button_press: Error(Nil),
        self_subject: Ok(self_subject),
        timer_interval_ms: timer_interval_ms,
        send_after: send_after,
        timer_handle: initial_timer_handle,
      )

    actor.initialised(initial_state)
    |> actor.returning(self_subject)
    |> Ok
  })
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
          log.actor_debug(
            "HouseMode",
            "Sleep button pressed at "
              <> int.to_string(current_hour)
              <> ":00 → "
              <> log.state_change(
                mode.house_mode_to_string(state.mode),
                "Sleeping",
              ),
          )
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
              log.actor_debug(
                "HouseMode",
                "Button pressed (before 8pm) → "
                  <> log.state_change(
                    mode.house_mode_to_string(state.mode),
                    mode.house_mode_to_string(new_mode),
                  ),
              )
              broadcast_mode_change(new_state.room_actors, new_mode)
              actor.continue(State(..new_state, mode: new_mode))
            }
            False -> actor.continue(new_state)
          }
        }
      }
    }
    WakeUp -> {
      log.actor_debug(
        "HouseMode",
        "WakeUp triggered → "
          <> log.state_change(mode.house_mode_to_string(state.mode), "Auto"),
      )
      // Clear button press and set to Auto
      let new_state =
        State(..state, last_button_press: Error(Nil), mode: HouseModeAuto)
      broadcast_mode_change(new_state.room_actors, HouseModeAuto)
      actor.continue(new_state)
    }
    RegisterRoomActor(room_actor) -> {
      // Send current mode immediately so the new room actor has correct state
      process.send(room_actor, room_actor.HouseModeChanged(state.mode))
      actor.continue(
        State(..state, room_actors: [room_actor, ..state.room_actors]),
      )
    }
    ReEvaluateMode -> {
      // Re-evaluate mode based on current time
      let current_time = state.get_now()
      let new_mode = evaluate_mode(current_time, state.last_button_press)
      let new_state = case new_mode != state.mode {
        True -> {
          log.actor_debug(
            "HouseMode",
            "Timer re-evaluation at "
              <> int.to_string(datetime_hour(current_time))
              <> ":00 → "
              <> log.state_change(
                mode.house_mode_to_string(state.mode),
                mode.house_mode_to_string(new_mode),
              ),
          )
          broadcast_mode_change(state.room_actors, new_mode)
          State(..state, mode: new_mode)
        }
        False -> state
      }
      // Reschedule the timer for the next evaluation and store handle
      let new_timer_handle = reschedule_timer(new_state)
      actor.continue(State(..new_state, timer_handle: new_timer_handle))
    }

    Shutdown -> {
      // Cancel the timer if present
      case state.timer_handle {
        Ok(handle) -> timer.cancel_handle(handle)
        Error(_) -> Nil
      }
      // Stop the actor
      actor.stop()
    }
  }
}

/// Reschedule the timer for the next evaluation cycle
/// Returns the new timer handle (or Error(Nil) if no timer scheduled)
fn reschedule_timer(state: State) -> Result(TimerHandle, Nil) {
  case state.self_subject, state.timer_interval_ms > 0 {
    Ok(self), True -> {
      let handle =
        state.send_after(self, state.timer_interval_ms, ReEvaluateMode)
      Ok(handle)
    }
    _, _ -> Error(Nil)
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
