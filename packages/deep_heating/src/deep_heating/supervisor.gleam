//// DeepHeatingSupervisor - top-level OTP supervision tree for Deep Heating.
////
//// Supervision tree structure:
//// ```
//// DeepHeatingSupervisor (one_for_one)
//// ├── HouseModeActor
//// ├── StateAggregatorActor
//// └── (more children will be added later)
//// ```

import deep_heating/actor/house_mode_actor
import deep_heating/actor/state_aggregator_actor
import gleam/erlang/process.{type Name, type Pid, type Subject}
import gleam/otp/actor
import gleam/otp/static_supervisor as supervisor

/// Handle to the running supervisor and its children
pub opaque type Supervisor {
  Supervisor(
    pid: Pid,
    house_mode_name: Name(house_mode_actor.Message),
    state_aggregator_name: Name(state_aggregator_actor.Message),
  )
}

/// Reference to a running actor with its PID
pub type ActorRef(msg) {
  ActorRef(pid: Pid, subject: Subject(msg))
}

/// Start the Deep Heating supervision tree.
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
  |> wrap_result(house_mode_name, state_aggregator_name)
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

/// Get the supervisor's PID
pub fn pid(sup: Supervisor) -> Pid {
  sup.pid
}

fn wrap_result(
  result: Result(actor.Started(supervisor.Supervisor), actor.StartError),
  house_mode_name: Name(house_mode_actor.Message),
  state_aggregator_name: Name(state_aggregator_actor.Message),
) -> Result(actor.Started(Supervisor), actor.StartError) {
  case result {
    Ok(started) -> {
      let sup =
        Supervisor(
          pid: started.pid,
          house_mode_name: house_mode_name,
          state_aggregator_name: state_aggregator_name,
        )
      Ok(actor.Started(pid: started.pid, data: sup))
    }
    Error(e) -> Error(e)
  }
}
