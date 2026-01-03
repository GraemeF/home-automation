//// HaCommandActor - sends commands to Home Assistant.
////
//// Responsibilities:
//// - Receive SetTrvTarget and SetTrvMode commands
//// - Debounce per-TRV (5 seconds) before calling HA API
//// - Send both mode and temperature in parallel after debounce
//// - Handle errors gracefully (log but don't crash)

import deep_heating/entity_id.{type ClimateEntityId}
import deep_heating/home_assistant.{type HaClient}
import deep_heating/mode.{type HvacMode}
import deep_heating/temperature.{type Temperature}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/io
import gleam/otp/actor

/// API calls that were made (for testing/observability)
pub type ApiCall {
  TrvApiCall(entity_id: ClimateEntityId, mode: HvacMode, target: Temperature)
  HeatingApiCall(
    entity_id: ClimateEntityId,
    mode: HvacMode,
    target: Temperature,
  )
}

/// Pending action waiting for debounce timer
type PendingAction {
  PendingAction(mode: HvacMode, target: Temperature)
}

/// Pending heating action with entity ID
type PendingHeatingAction {
  PendingHeatingAction(
    entity_id: ClimateEntityId,
    mode: HvacMode,
    target: Temperature,
  )
}

/// Messages handled by the HaCommandActor
pub type Message {
  /// Combined TRV action with both mode and target
  SetTrvAction(entity_id: ClimateEntityId, mode: HvacMode, target: Temperature)
  /// Combined heating action with both mode and target
  SetHeatingAction(
    entity_id: ClimateEntityId,
    mode: HvacMode,
    target: Temperature,
  )
  /// Internal: debounce timer fired for a TRV
  TrvDebounceTimeout(entity_id: ClimateEntityId)
  /// Internal: debounce timer fired for heating
  HeatingDebounceTimeout
}

/// Internal actor state
type State {
  State(
    ha_client: HaClient,
    api_spy: Subject(ApiCall),
    debounce_ms: Int,
    self_subject: Subject(Message),
    /// Pending TRV actions waiting for debounce
    pending_trv_actions: Dict(ClimateEntityId, PendingAction),
    /// Pending heating action waiting for debounce
    pending_heating_action: Result(PendingHeatingAction, Nil),
    /// Track which entities have active timers
    active_trv_timers: Dict(ClimateEntityId, Bool),
    /// Track if heating timer is active
    heating_timer_active: Bool,
  )
}

/// Start the HaCommandActor with the given HA client
pub fn start(
  ha_client ha_client: HaClient,
  api_spy api_spy: Subject(ApiCall),
  debounce_ms debounce_ms: Int,
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  actor.new_with_initialiser(1000, fn(self_subject) {
    let initial_state =
      State(
        ha_client: ha_client,
        api_spy: api_spy,
        debounce_ms: debounce_ms,
        self_subject: self_subject,
        pending_trv_actions: dict.new(),
        pending_heating_action: Error(Nil),
        active_trv_timers: dict.new(),
        heating_timer_active: False,
      )
    actor.initialised(initial_state)
    |> actor.returning(self_subject)
    |> Ok
  })
  |> actor.on_message(handle_message)
  |> actor.start
}

fn handle_message(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    SetTrvAction(entity_id, hvac_mode, target) -> {
      // Store the pending action (overwrites any previous)
      let new_pending =
        dict.insert(
          state.pending_trv_actions,
          entity_id,
          PendingAction(mode: hvac_mode, target: target),
        )

      // Start debounce timer if not already running for this entity
      let has_timer =
        dict.get(state.active_trv_timers, entity_id)
        |> result_to_bool

      let new_timers = case has_timer {
        True -> state.active_trv_timers
        False -> {
          // Start timer - send message to self after debounce period
          process.send_after(
            state.self_subject,
            state.debounce_ms,
            TrvDebounceTimeout(entity_id),
          )
          dict.insert(state.active_trv_timers, entity_id, True)
        }
      }

      actor.continue(
        State(
          ..state,
          pending_trv_actions: new_pending,
          active_trv_timers: new_timers,
        ),
      )
    }

    TrvDebounceTimeout(entity_id) -> {
      // Timer fired - execute the pending action
      case dict.get(state.pending_trv_actions, entity_id) {
        Ok(PendingAction(hvac_mode, target)) -> {
          // Notify spy for testing/observability
          process.send(
            state.api_spy,
            TrvApiCall(entity_id: entity_id, mode: hvac_mode, target: target),
          )

          // Call HA API - spawn processes for parallel execution
          // Note: We ignore the result as we're fire-and-forget
          let ha_client = state.ha_client
          let eid = entity_id

          // Spawn unlinked processes for parallel execution
          // Using spawn_unlinked so failures don't crash the actor
          let _temp_pid =
            process.spawn_unlinked(fn() {
              case home_assistant.set_temperature(ha_client, eid, target) {
                Ok(_) -> Nil
                Error(err) -> {
                  io.println(
                    "TRV set_temperature failed: " <> ha_error_to_string(err),
                  )
                }
              }
            })

          let _mode_pid =
            process.spawn_unlinked(fn() {
              case home_assistant.set_hvac_mode(ha_client, eid, hvac_mode) {
                Ok(_) -> Nil
                Error(err) -> {
                  io.println(
                    "TRV set_hvac_mode failed: " <> ha_error_to_string(err),
                  )
                }
              }
            })

          // Clear pending action and timer flag
          let new_pending = dict.delete(state.pending_trv_actions, entity_id)
          let new_timers = dict.delete(state.active_trv_timers, entity_id)

          actor.continue(
            State(
              ..state,
              pending_trv_actions: new_pending,
              active_trv_timers: new_timers,
            ),
          )
        }
        Error(_) -> {
          // No pending action, just clear timer
          let new_timers = dict.delete(state.active_trv_timers, entity_id)
          actor.continue(State(..state, active_trv_timers: new_timers))
        }
      }
    }

    SetHeatingAction(entity_id, hvac_mode, target) -> {
      // Store the pending heating action (overwrites any previous)
      let new_pending =
        Ok(PendingHeatingAction(
          entity_id: entity_id,
          mode: hvac_mode,
          target: target,
        ))

      // Start debounce timer if not already running
      let new_timer_active = case state.heating_timer_active {
        True -> True
        False -> {
          // Start timer
          process.send_after(
            state.self_subject,
            state.debounce_ms,
            HeatingDebounceTimeout,
          )
          True
        }
      }

      actor.continue(
        State(
          ..state,
          pending_heating_action: new_pending,
          heating_timer_active: new_timer_active,
        ),
      )
    }

    HeatingDebounceTimeout -> {
      // Timer fired - execute the pending heating action
      case state.pending_heating_action {
        Ok(PendingHeatingAction(entity_id, hvac_mode, target)) -> {
          // Notify the spy for testing/observability
          process.send(
            state.api_spy,
            HeatingApiCall(
              entity_id: entity_id,
              mode: hvac_mode,
              target: target,
            ),
          )

          // Call HA API - spawn unlinked processes for parallel execution
          let ha_client = state.ha_client
          let eid = entity_id

          let _temp_pid =
            process.spawn_unlinked(fn() {
              case home_assistant.set_temperature(ha_client, eid, target) {
                Ok(_) -> Nil
                Error(err) -> {
                  io.println(
                    "Heating set_temperature failed: "
                    <> ha_error_to_string(err),
                  )
                }
              }
            })

          let _mode_pid =
            process.spawn_unlinked(fn() {
              case home_assistant.set_hvac_mode(ha_client, eid, hvac_mode) {
                Ok(_) -> Nil
                Error(err) -> {
                  io.println(
                    "Heating set_hvac_mode failed: " <> ha_error_to_string(err),
                  )
                }
              }
            })

          // Clear pending action and timer flag
          actor.continue(
            State(
              ..state,
              pending_heating_action: Error(Nil),
              heating_timer_active: False,
            ),
          )
        }
        Error(_) -> {
          // No pending action, just clear timer
          actor.continue(State(..state, heating_timer_active: False))
        }
      }
    }
  }
}

fn result_to_bool(r: Result(a, b)) -> Bool {
  case r {
    Ok(_) -> True
    Error(_) -> False
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
