//// LoggingCommandActor - dry-run mode that logs commands instead of sending to HA.
////
//// Used when DRY_RUN=true to run the full application logic but only log
//// what would be sent to Home Assistant, without actually controlling TRVs.
////
//// Unlike HaCommandActor, this has no debouncing - commands are logged immediately.

import deep_heating/entity_id
import deep_heating/home_assistant/ha_command_actor.{
  type ApiCall, type Message, HeatingApiCall, HeatingDebounceTimeout,
  SetHeatingAction, SetTrvAction, Shutdown, TrvApiCall, TrvDebounceTimeout,
}
import deep_heating/log
import deep_heating/mode
import deep_heating/temperature
import gleam/erlang/process.{type Name, type Subject}
import gleam/otp/actor

/// Internal actor state
type State {
  State(api_spy: Subject(ApiCall))
}

/// Start the LoggingCommandActor
pub fn start(
  api_spy api_spy: Subject(ApiCall),
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  actor.new(State(api_spy: api_spy))
  |> actor.on_message(handle_message)
  |> actor.start
}

/// Start the LoggingCommandActor with a registered name.
/// Uses actor.named() so it can be found via process.named_subject().
pub fn start_named(
  name name: Name(Message),
  api_spy api_spy: Subject(ApiCall),
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  actor.new(State(api_spy: api_spy))
  |> actor.named(name)
  |> actor.on_message(handle_message)
  |> actor.start
}

fn handle_message(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    SetTrvAction(entity_id, hvac_mode, target) -> {
      let entity_id_str = entity_id.climate_entity_id_to_string(entity_id)
      log.entity_info(
        entity_id_str,
        "[DRY RUN] TRV command: mode="
          <> mode.hvac_mode_to_string(hvac_mode)
          <> ", target="
          <> temperature.format(target),
      )

      // Notify spy for testing/observability
      process.send(
        state.api_spy,
        TrvApiCall(entity_id: entity_id, mode: hvac_mode, target: target),
      )

      actor.continue(state)
    }

    SetHeatingAction(entity_id, hvac_mode, target) -> {
      let entity_id_str = entity_id.climate_entity_id_to_string(entity_id)
      log.entity_info(
        entity_id_str,
        "[DRY RUN] Boiler command: mode="
          <> mode.hvac_mode_to_string(hvac_mode)
          <> ", target="
          <> temperature.format(target),
      )

      // Notify spy for testing/observability
      process.send(
        state.api_spy,
        HeatingApiCall(entity_id: entity_id, mode: hvac_mode, target: target),
      )

      actor.continue(state)
    }

    // These are internal to HaCommandActor's debouncing - ignore them
    TrvDebounceTimeout(_) -> actor.continue(state)
    HeatingDebounceTimeout -> actor.continue(state)

    Shutdown -> actor.stop()
  }
}
