//// DeepHeatingSupervisor - top-level OTP supervision tree for Deep Heating.
////
//// Supervision tree structure:
//// ```
//// DeepHeatingSupervisor (one_for_one)
//// ├── HouseModeActor
//// ├── StateAggregatorActor
//// └── HaPollerActor (when started with config)
//// ```

import deep_heating/actor/ha_poller_actor
import deep_heating/actor/house_mode_actor
import deep_heating/actor/state_aggregator_actor
import deep_heating/home_assistant.{type HaClient}
import gleam/erlang/process.{type Name, type Pid, type Subject}
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/static_supervisor as supervisor

/// Handle to the running supervisor and its children
pub opaque type Supervisor {
  Supervisor(
    pid: Pid,
    house_mode_name: Name(house_mode_actor.Message),
    state_aggregator_name: Name(state_aggregator_actor.Message),
    ha_poller_name: Option(Name(ha_poller_actor.Message)),
  )
}

/// Configuration for starting the supervisor with HaPollerActor
pub type SupervisorConfig {
  SupervisorConfig(
    ha_client: HaClient,
    poller_config: ha_poller_actor.PollerConfig,
  )
}

/// Reference to a running actor with its PID
pub type ActorRef(msg) {
  ActorRef(pid: Pid, subject: Subject(msg))
}

/// Start the Deep Heating supervision tree without HaPollerActor.
///
/// Returns a Started record containing the supervisor PID and a handle
/// for querying child actors.
pub fn start() -> Result(actor.Started(Supervisor), actor.StartError) {
  // Create names for our actors so we can look them up later
  let house_mode_name = process.new_name("deep_heating_house_mode")
  let state_aggregator_name = process.new_name("deep_heating_state_aggregator")

  // Build and start the supervision tree
  supervisor.new(supervisor.OneForOne)
  |> supervisor.add(house_mode_actor.child_spec(house_mode_name))
  |> supervisor.add(state_aggregator_actor.child_spec(state_aggregator_name))
  |> supervisor.start
  |> wrap_result(house_mode_name, state_aggregator_name, None)
}

/// Start the Deep Heating supervision tree with HaPollerActor.
///
/// This variant includes the HaPollerActor for polling Home Assistant.
pub fn start_with_config(
  config: SupervisorConfig,
) -> Result(actor.Started(Supervisor), actor.StartError) {
  // Create names for our actors so we can look them up later
  let house_mode_name = process.new_name("deep_heating_house_mode")
  let state_aggregator_name = process.new_name("deep_heating_state_aggregator")
  let ha_poller_name = process.new_name("deep_heating_ha_poller")

  // Build and start the supervision tree
  supervisor.new(supervisor.OneForOne)
  |> supervisor.add(house_mode_actor.child_spec(house_mode_name))
  |> supervisor.add(state_aggregator_actor.child_spec(state_aggregator_name))
  |> supervisor.add(ha_poller_actor.child_spec(
    ha_poller_name,
    config.ha_client,
    config.poller_config,
  ))
  |> supervisor.start
  |> wrap_result(house_mode_name, state_aggregator_name, Some(ha_poller_name))
}

/// Get a reference to the HouseModeActor
pub fn get_house_mode_actor(
  sup: Supervisor,
) -> Result(ActorRef(house_mode_actor.Message), Nil) {
  case process.named(sup.house_mode_name) {
    Ok(pid) -> {
      let subject = process.named_subject(sup.house_mode_name)
      Ok(ActorRef(pid: pid, subject: subject))
    }
    Error(_) -> Error(Nil)
  }
}

/// Get a reference to the StateAggregatorActor
pub fn get_state_aggregator(
  sup: Supervisor,
) -> Result(ActorRef(state_aggregator_actor.Message), Nil) {
  case process.named(sup.state_aggregator_name) {
    Ok(pid) -> {
      let subject = process.named_subject(sup.state_aggregator_name)
      Ok(ActorRef(pid: pid, subject: subject))
    }
    Error(_) -> Error(Nil)
  }
}

/// Get a reference to the HaPollerActor (only available if started with config)
pub fn get_ha_poller(
  sup: Supervisor,
) -> Result(ActorRef(ha_poller_actor.Message), Nil) {
  case sup.ha_poller_name {
    Some(name) -> {
      case process.named(name) {
        Ok(pid) -> {
          let subject = process.named_subject(name)
          Ok(ActorRef(pid: pid, subject: subject))
        }
        Error(_) -> Error(Nil)
      }
    }
    None -> Error(Nil)
  }
}

/// Get the supervisor's PID
pub fn pid(sup: Supervisor) -> Pid {
  sup.pid
}

fn wrap_result(
  result: Result(actor.Started(supervisor.Supervisor), actor.StartError),
  house_mode_name: Name(house_mode_actor.Message),
  state_aggregator_name: Name(state_aggregator_actor.Message),
  ha_poller_name: Option(Name(ha_poller_actor.Message)),
) -> Result(actor.Started(Supervisor), actor.StartError) {
  case result {
    Ok(started) -> {
      let sup =
        Supervisor(
          pid: started.pid,
          house_mode_name: house_mode_name,
          state_aggregator_name: state_aggregator_name,
          ha_poller_name: ha_poller_name,
        )
      Ok(actor.Started(pid: started.pid, data: sup))
    }
    Error(e) -> Error(e)
  }
}
