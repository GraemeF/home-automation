//// HaPollerActor - polls Home Assistant for state updates.
////
//// Responsibilities:
//// - Poll HA API every N seconds (configurable)
//// - Parse climate entities into TrvUpdate messages
//// - Parse main heating entity into HeatingUpdate
//// - Detect goodnight button/event for SleepButtonPressed
//// - Dispatch updates to appropriate actors
//// - Filter to only managed TRVs (those with schedules)

import deep_heating/entity_id.{type ClimateEntityId, type SensorEntityId}
import deep_heating/home_assistant/client.{type HaClient} as home_assistant
import deep_heating/log
import deep_heating/rooms/trv_actor.{type TrvUpdate, TrvUpdate}
import deep_heating/temperature.{type Temperature}
import deep_heating/timer.{type SendAfter, type TimerHandle}
import gleam/erlang/process.{type Name, type Subject}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/otp/supervision
import gleam/set.{type Set}

/// Messages handled by the HaPollerActor
pub type Message {
  /// Start polling
  StartPolling
  /// Stop polling
  StopPolling
  /// Internal: poll timer fired
  PollNow
  /// Configure polling interval
  Configure(interval_ms: Int)
  /// For testing: inject a mock JSON response for the next poll
  InjectMockResponse(json: String)
  /// For testing: inject a mock error for the next poll
  InjectMockError(error: home_assistant.HaError)
  /// Gracefully stop the actor, cancelling any pending poll timer
  Shutdown
}

/// Configuration for the poller
pub type PollerConfig {
  PollerConfig(
    /// Interval between polls in milliseconds
    poll_interval_ms: Int,
    /// Entity ID for the main heating system
    heating_entity_id: ClimateEntityId,
    /// Entity ID for the sleep button
    sleep_button_entity_id: String,
    /// Set of TRV entity IDs that have schedules (managed TRVs)
    managed_trv_ids: Set(ClimateEntityId),
    /// Set of sensor entity IDs for external temperature sensors
    managed_sensor_ids: Set(SensorEntityId),
  )
}

/// Events dispatched by the poller
pub type PollerEvent {
  /// TRV state update
  TrvUpdated(entity_id: ClimateEntityId, update: TrvUpdate)
  /// Temperature sensor update
  SensorUpdated(
    entity_id: SensorEntityId,
    temperature: option.Option(Temperature),
  )
  /// Heating system status changed
  HeatingStatusChanged(is_heating: Bool)
  /// Sleep button was pressed
  SleepButtonPressed
  /// Polling started
  PollingStarted
  /// Polling stopped
  PollingStopped
  /// Poll completed
  PollCompleted
  /// Poll failed
  PollFailed(error: String)
  /// Exponential backoff was applied (next poll delayed)
  BackoffApplied(delay_ms: Int)
  /// Backoff was reset after successful poll
  BackoffReset
}

/// Maximum backoff delay in milliseconds (60 seconds)
const max_backoff_ms = 60_000

/// Internal actor state
type State {
  State(
    ha_client: HaClient,
    config: PollerConfig,
    event_spy: Subject(PollerEvent),
    self_subject: Subject(Message),
    is_polling: Bool,
    last_sleep_button_state: String,
    /// For testing: mock JSON response to use instead of calling HA
    mock_response: option.Option(String),
    /// For testing: mock error to return instead of calling HA
    mock_error: option.Option(home_assistant.HaError),
    /// Current backoff multiplier (1 = no backoff, 2 = doubled, etc.)
    backoff_multiplier: Int,
    /// Injectable send_after function for deterministic timer testing
    send_after: SendAfter(Message),
    /// Handle to the current poll timer (for cancellation on shutdown)
    timer_handle: Result(TimerHandle, Nil),
  )
}

/// Start the HaPollerActor with default real_send_after
pub fn start(
  ha_client ha_client: HaClient,
  config config: PollerConfig,
  event_spy event_spy: Subject(PollerEvent),
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  start_with_send_after(
    ha_client: ha_client,
    config: config,
    event_spy: event_spy,
    send_after: timer.real_send_after,
  )
}

/// Start the HaPollerActor with injectable send_after (for testing)
pub fn start_with_send_after(
  ha_client ha_client: HaClient,
  config config: PollerConfig,
  event_spy event_spy: Subject(PollerEvent),
  send_after send_after: SendAfter(Message),
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  actor.new_with_initialiser(1000, fn(self_subject) {
    let initial_state =
      State(
        ha_client: ha_client,
        config: config,
        event_spy: event_spy,
        self_subject: self_subject,
        is_polling: False,
        last_sleep_button_state: "",
        mock_response: None,
        mock_error: None,
        backoff_multiplier: 1,
        send_after: send_after,
        timer_handle: Error(Nil),
      )
    actor.initialised(initial_state)
    |> actor.returning(self_subject)
    |> Ok
  })
  |> actor.on_message(handle_message)
  |> actor.start
}

/// Start the HaPollerActor and register it with the given name.
/// Events are sent to the provided event_spy subject.
/// Uses default real_send_after.
pub fn start_named(
  name: Name(Message),
  ha_client: HaClient,
  config: PollerConfig,
  event_spy: Subject(PollerEvent),
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  start_named_with_send_after(
    name: name,
    ha_client: ha_client,
    config: config,
    event_spy: event_spy,
    send_after: timer.real_send_after,
  )
}

/// Start the HaPollerActor with injectable send_after and register with given name.
pub fn start_named_with_send_after(
  name name: Name(Message),
  ha_client ha_client: HaClient,
  config config: PollerConfig,
  event_spy event_spy: Subject(PollerEvent),
  send_after send_after: SendAfter(Message),
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  actor.new_with_initialiser(1000, fn(self_subject) {
    let initial_state =
      State(
        ha_client: ha_client,
        config: config,
        event_spy: event_spy,
        self_subject: self_subject,
        is_polling: False,
        last_sleep_button_state: "",
        mock_response: None,
        mock_error: None,
        backoff_multiplier: 1,
        send_after: send_after,
        timer_handle: Error(Nil),
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
  ha_client: HaClient,
  config: PollerConfig,
  event_spy: Subject(PollerEvent),
) -> supervision.ChildSpecification(Subject(Message)) {
  supervision.worker(fn() { start_named(name, ha_client, config, event_spy) })
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

fn handle_message(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    StartPolling -> {
      log.info("Polling started")
      // Emit PollingStarted event
      process.send(state.event_spy, PollingStarted)
      // Schedule first poll immediately
      process.send(state.self_subject, PollNow)
      actor.continue(State(..state, is_polling: True))
    }
    StopPolling -> {
      log.info("Polling stopped")
      // Emit PollingStopped event
      process.send(state.event_spy, PollingStopped)
      actor.continue(State(..state, is_polling: False))
    }
    PollNow -> {
      log.debug("Polling Home Assistant...")
      // Get JSON either from mock error, mock response, or real HA
      let json_result = case state.mock_error {
        Some(err) -> Error(err)
        None ->
          case state.mock_response {
            Some(json) -> Ok(json)
            None -> home_assistant.get_states(state.ha_client)
          }
      }

      // Determine if poll succeeded and calculate new backoff state
      let poll_succeeded = case json_result {
        Ok(_) -> True
        Error(_) -> False
      }

      // Calculate new backoff multiplier (doubles on each failure, resets on success)
      let new_backoff_multiplier = case poll_succeeded {
        True -> 1
        False -> state.backoff_multiplier * 2
      }

      // Track new sleep button state for state update
      let new_sleep_button_state = case json_result {
        Ok(json) -> {
          // Parse climate entities and dispatch TRV updates
          case home_assistant.parse_climate_entities(json) {
            Ok(entities) -> {
              // Filter to managed TRVs and dispatch updates
              entities
              |> list.filter(fn(entity) {
                set.contains(state.config.managed_trv_ids, entity.entity_id)
              })
              |> list.each(fn(entity) {
                let update =
                  TrvUpdate(
                    temperature: entity.current_temperature,
                    target: entity.target_temperature,
                    mode: entity.hvac_mode,
                    is_heating: entity.is_heating,
                  )
                process.send(
                  state.event_spy,
                  TrvUpdated(entity.entity_id, update),
                )
              })

              // Find heating entity and emit HeatingStatusChanged
              entities
              |> list.find(fn(entity) {
                entity.entity_id == state.config.heating_entity_id
              })
              |> option.from_result
              |> option.map(fn(heating_entity) {
                process.send(
                  state.event_spy,
                  HeatingStatusChanged(heating_entity.is_heating),
                )
              })
              Nil
            }
            Error(_) -> Nil
          }

          // Parse sensor entities and dispatch sensor updates
          case home_assistant.parse_sensor_entities(json) {
            Ok(sensors) -> {
              // Filter to managed sensors and dispatch updates
              sensors
              |> list.filter(fn(sensor) {
                set.contains(state.config.managed_sensor_ids, sensor.entity_id)
              })
              |> list.each(fn(sensor) {
                process.send(
                  state.event_spy,
                  SensorUpdated(sensor.entity_id, sensor.temperature),
                )
              })
              Nil
            }
            Error(_) -> Nil
          }

          // Check for sleep button state change
          case
            home_assistant.find_input_button_state(
              json,
              state.config.sleep_button_entity_id,
            )
          {
            Ok(new_state) -> {
              // Only emit event if state changed and not first poll
              case
                state.last_sleep_button_state != ""
                && new_state != state.last_sleep_button_state
              {
                True -> process.send(state.event_spy, SleepButtonPressed)
                False -> Nil
              }
              new_state
            }
            Error(_) -> state.last_sleep_button_state
          }
        }
        Error(err) -> {
          log.error("Poll failed: " <> home_assistant.error_to_string(err))
          process.send(
            state.event_spy,
            PollFailed(home_assistant.error_to_string(err)),
          )
          state.last_sleep_button_state
        }
      }

      // Emit PollCompleted/PollFailed followed by backoff events
      case json_result {
        Ok(_) -> {
          log.debug("Poll succeeded")
          process.send(state.event_spy, PollCompleted)
          // Emit BackoffReset if we were in backoff state
          case state.backoff_multiplier > 1 {
            True -> process.send(state.event_spy, BackoffReset)
            False -> Nil
          }
        }
        Error(_) -> {
          // BackoffApplied comes after PollFailed
          let delay_ms =
            int.min(
              state.config.poll_interval_ms * new_backoff_multiplier,
              max_backoff_ms,
            )
          process.send(state.event_spy, BackoffApplied(delay_ms))
        }
      }

      // Schedule next poll if still polling and capture timer handle
      let new_timer_handle = case state.is_polling {
        True -> {
          let delay_ms = case poll_succeeded {
            True -> state.config.poll_interval_ms
            False ->
              int.min(
                state.config.poll_interval_ms * new_backoff_multiplier,
                max_backoff_ms,
              )
          }
          let handle =
            state.send_after(state.self_subject, delay_ms, PollNow)
          Ok(handle)
        }
        False -> Error(Nil)
      }

      // Clear mock response/error and update state
      actor.continue(
        State(
          ..state,
          mock_response: None,
          mock_error: None,
          last_sleep_button_state: new_sleep_button_state,
          backoff_multiplier: new_backoff_multiplier,
          timer_handle: new_timer_handle,
        ),
      )
    }
    Configure(interval_ms) -> {
      let new_config =
        PollerConfig(..state.config, poll_interval_ms: interval_ms)
      actor.continue(State(..state, config: new_config))
    }
    InjectMockResponse(json) -> {
      actor.continue(State(..state, mock_response: Some(json)))
    }
    InjectMockError(error) -> {
      actor.continue(State(..state, mock_error: Some(error)))
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
