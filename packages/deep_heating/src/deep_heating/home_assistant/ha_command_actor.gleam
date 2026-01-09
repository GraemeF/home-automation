//// HaCommandActor - sends commands to Home Assistant.
////
//// Responsibilities:
//// - Receive SetTrvTarget and SetTrvMode commands
//// - Debounce per-TRV (5 seconds) before calling HA API
//// - Send both mode and temperature in parallel after debounce
//// - Handle errors gracefully (log but don't crash)

import deep_heating/entity_id.{type ClimateEntityId}
import deep_heating/home_assistant/client.{type HaClient} as home_assistant
import deep_heating/mode.{type HvacMode}
import deep_heating/temperature.{type Temperature}
import deep_heating/timer.{type SendAfter, type TimerHandle}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Name, type Subject}
import gleam/otp/actor
import gleam/otp/supervision

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
  /// Gracefully stop the actor, cancelling all pending timers
  Shutdown
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
    /// Active TRV timer handles (can be cancelled)
    active_trv_timers: Dict(ClimateEntityId, TimerHandle),
    /// Active heating timer handle (can be cancelled)
    heating_timer_handle: Result(TimerHandle, Nil),
    /// Skip real HTTP calls (for testing)
    skip_http: Bool,
    /// Injectable send_after function for timers
    send_after: SendAfter(Message),
  )
}

/// Start the HaCommandActor with the given HA client
pub fn start(
  ha_client ha_client: HaClient,
  api_spy api_spy: Subject(ApiCall),
  debounce_ms debounce_ms: Int,
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  start_with_options(
    ha_client: ha_client,
    api_spy: api_spy,
    debounce_ms: debounce_ms,
    skip_http: False,
    send_after: timer.real_send_after,
  )
}

/// Start the HaCommandActor with options (for testing)
pub fn start_with_options(
  ha_client ha_client: HaClient,
  api_spy api_spy: Subject(ApiCall),
  debounce_ms debounce_ms: Int,
  skip_http skip_http: Bool,
  send_after send_after: SendAfter(Message),
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
        heating_timer_handle: Error(Nil),
        skip_http: skip_http,
        send_after: send_after,
      )
    actor.initialised(initial_state)
    |> actor.returning(self_subject)
    |> Ok
  })
  |> actor.on_message(handle_message)
  |> actor.start
}

/// Start the HaCommandActor and register it with the given name.
/// Uses actor.named() so the actor can be found via named_subject() after restarts.
pub fn start_named(
  name: Name(Message),
  ha_client: HaClient,
  debounce_ms: Int,
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  // Create an internal spy - events are not observed in production
  let api_spy: Subject(ApiCall) = process.new_subject()

  start_named_with_options(
    name: name,
    ha_client: ha_client,
    api_spy: api_spy,
    debounce_ms: debounce_ms,
    skip_http: False,
    send_after: timer.real_send_after,
  )
}

/// Start the HaCommandActor with a name and options (for testing).
/// Uses actor.named() so the actor can be found via named_subject() after restarts.
pub fn start_named_with_options(
  name name: Name(Message),
  ha_client ha_client: HaClient,
  api_spy api_spy: Subject(ApiCall),
  debounce_ms debounce_ms: Int,
  skip_http skip_http: Bool,
  send_after send_after: SendAfter(Message),
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
        heating_timer_handle: Error(Nil),
        skip_http: skip_http,
        send_after: send_after,
      )
    actor.initialised(initial_state)
    |> actor.returning(self_subject)
    |> Ok
  })
  |> actor.named(name)
  |> actor.on_message(handle_message)
  |> actor.start
}

/// Create a child specification for supervision
pub fn child_spec(
  name: Name(Message),
  ha_client: HaClient,
  debounce_ms: Int,
) -> supervision.ChildSpecification(Subject(Message)) {
  supervision.worker(fn() { start_named(name, ha_client, debounce_ms) })
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

      // Cancel existing timer if present (true debounce: reset on each new command)
      case dict.get(state.active_trv_timers, entity_id) {
        Ok(existing_handle) -> timer.cancel_handle(existing_handle)
        Error(_) -> Nil
      }

      // Start new timer - send message to self after debounce period
      let handle =
        state.send_after(
          state.self_subject,
          state.debounce_ms,
          TrvDebounceTimeout(entity_id),
        )
      let new_timers = dict.insert(state.active_trv_timers, entity_id, handle)

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

          // Call HA API unless skip_http is enabled (for testing)
          case state.skip_http {
            True -> Nil
            False -> {
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
                    Error(_) -> Nil
                  }
                })

              let _mode_pid =
                process.spawn_unlinked(fn() {
                  case home_assistant.set_hvac_mode(ha_client, eid, hvac_mode) {
                    Ok(_) -> Nil
                    Error(_) -> Nil
                  }
                })

              Nil
            }
          }

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

      // Cancel existing timer if present (true debounce: reset on each new command)
      case state.heating_timer_handle {
        Ok(existing_handle) -> timer.cancel_handle(existing_handle)
        Error(_) -> Nil
      }

      // Start new timer
      let handle =
        state.send_after(
          state.self_subject,
          state.debounce_ms,
          HeatingDebounceTimeout,
        )

      actor.continue(
        State(
          ..state,
          pending_heating_action: new_pending,
          heating_timer_handle: Ok(handle),
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

          // Call HA API unless skip_http is enabled (for testing)
          case state.skip_http {
            True -> Nil
            False -> {
              // Call HA API - spawn unlinked processes for parallel execution
              let ha_client = state.ha_client
              let eid = entity_id

              let _temp_pid =
                process.spawn_unlinked(fn() {
                  case home_assistant.set_temperature(ha_client, eid, target) {
                    Ok(_) -> Nil
                    Error(_) -> Nil
                  }
                })

              let _mode_pid =
                process.spawn_unlinked(fn() {
                  case home_assistant.set_hvac_mode(ha_client, eid, hvac_mode) {
                    Ok(_) -> Nil
                    Error(_) -> Nil
                  }
                })

              Nil
            }
          }

          // Clear pending action and timer handle (timer already fired)
          actor.continue(
            State(
              ..state,
              pending_heating_action: Error(Nil),
              heating_timer_handle: Error(Nil),
            ),
          )
        }
        Error(_) -> {
          // No pending action, just clear timer handle
          actor.continue(State(..state, heating_timer_handle: Error(Nil)))
        }
      }
    }

    Shutdown -> {
      // Cancel all pending TRV timers
      dict.each(state.active_trv_timers, fn(_entity_id, handle) {
        timer.cancel_handle(handle)
      })

      // Cancel heating timer if present
      case state.heating_timer_handle {
        Ok(handle) -> timer.cancel_handle(handle)
        Error(_) -> Nil
      }

      // Stop the actor
      actor.stop()
    }
  }
}
