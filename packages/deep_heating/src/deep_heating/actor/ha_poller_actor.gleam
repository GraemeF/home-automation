//// HaPollerActor - polls Home Assistant for state updates.
////
//// Responsibilities:
//// - Poll HA API every N seconds (configurable)
//// - Parse climate entities into TrvUpdate messages
//// - Parse main heating entity into HeatingUpdate
//// - Detect goodnight button/event for SleepButtonPressed
//// - Dispatch updates to appropriate actors
//// - Filter to only managed TRVs (those with schedules)

import deep_heating/actor/trv_actor.{type TrvUpdate, TrvUpdate}
import deep_heating/entity_id.{type ClimateEntityId}
import deep_heating/home_assistant.{type HaClient}
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
  )
}

/// Events dispatched by the poller
pub type PollerEvent {
  /// TRV state update
  TrvUpdated(entity_id: ClimateEntityId, update: TrvUpdate)
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
}

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
  )
}

/// Start the HaPollerActor
pub fn start(
  ha_client ha_client: HaClient,
  config config: PollerConfig,
  event_spy event_spy: Subject(PollerEvent),
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
      )
    actor.initialised(initial_state)
    |> actor.returning(self_subject)
    |> Ok
  })
  |> actor.on_message(handle_message)
  |> actor.start
}

/// Start the HaPollerActor and register it with the given name
pub fn start_named(
  name: Name(Message),
  ha_client: HaClient,
  config: PollerConfig,
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  // Create an internal event spy - events are currently discarded
  // TODO: Route events to appropriate actors
  let event_spy: Subject(PollerEvent) = process.new_subject()

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
) -> supervision.ChildSpecification(Subject(Message)) {
  supervision.worker(fn() { start_named(name, ha_client, config) })
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
      // Emit PollingStarted event
      process.send(state.event_spy, PollingStarted)
      // Schedule first poll immediately
      process.send(state.self_subject, PollNow)
      actor.continue(State(..state, is_polling: True))
    }
    StopPolling -> {
      // Emit PollingStopped event
      process.send(state.event_spy, PollingStopped)
      actor.continue(State(..state, is_polling: False))
    }
    PollNow -> {
      // Get JSON either from mock or from real HA
      let json_result = case state.mock_response {
        Some(json) -> Ok(json)
        None -> home_assistant.get_states(state.ha_client)
      }

      // Track new sleep button state for state update
      let new_sleep_button_state = case json_result {
        Ok(json) -> {
          // Parse entities and dispatch updates
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
          process.send(state.event_spy, PollFailed(ha_error_to_string(err)))
          state.last_sleep_button_state
        }
      }

      // Emit PollCompleted if we got JSON successfully
      case json_result {
        Ok(_) -> process.send(state.event_spy, PollCompleted)
        Error(_) -> Nil
      }

      // Schedule next poll if still polling
      case state.is_polling {
        True -> {
          let _ =
            process.send_after(
              state.self_subject,
              state.config.poll_interval_ms,
              PollNow,
            )
          Nil
        }
        False -> Nil
      }

      // Clear mock response and update sleep button state
      actor.continue(
        State(
          ..state,
          mock_response: None,
          last_sleep_button_state: new_sleep_button_state,
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
  }
}

fn ha_error_to_string(err: home_assistant.HaError) -> String {
  case err {
    home_assistant.ConnectionError(msg) -> "ConnectionError: " <> msg
    home_assistant.AuthenticationError -> "AuthenticationError"
    home_assistant.EntityNotFound(entity_id) -> "EntityNotFound: " <> entity_id
    home_assistant.ApiError(status, body) ->
      "ApiError(" <> int.to_string(status) <> "): " <> body
    home_assistant.JsonParseError(msg) -> "JsonParseError: " <> msg
  }
}
