//// StateAggregatorActor - collects state snapshots for UI broadcasting.
////
//// Responsibilities:
//// - Receive state updates from all RoomActors
//// - Maintain complete DeepHeatingState
//// - Throttle updates (100ms) to avoid overwhelming clients
//// - Broadcast state to WebSocket client subscribers
//// - Persist room adjustments to disk when they change

import deep_heating/rooms/room_actor
import deep_heating/rooms/room_adjustments
import deep_heating/state.{type DeepHeatingState, type RoomState}
import deep_heating/timer.{type SendAfter}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Name, type Subject}
import gleam/list
import gleam/otp/actor
import gleam/otp/supervision

/// Throttle period in milliseconds
const throttle_ms: Int = 100

/// Messages handled by the StateAggregatorActor
pub type Message {
  /// Get the current aggregated state
  GetState(reply_to: Subject(DeepHeatingState))
  /// Subscribe to state updates (for WebSocket clients)
  Subscribe(subscriber: Subject(DeepHeatingState))
  /// Unsubscribe from state updates
  Unsubscribe(subscriber: Subject(DeepHeatingState))
  /// Room state was updated (from RoomActor)
  RoomUpdated(name: String, room_state: RoomState)
  /// Internal: broadcast to subscribers (triggered by throttle timer)
  Broadcast
  /// Register a RoomActor by name (for adjustment forwarding)
  RegisterRoomActor(name: String, actor: Subject(room_actor.Message))
  /// Adjust a room's temperature (forwarded to RoomActor)
  AdjustRoom(name: String, adjustment: Float)
}

/// Internal state of the aggregator
pub type State {
  State(
    current: DeepHeatingState,
    subscribers: List(Subject(DeepHeatingState)),
    broadcast_pending: Bool,
    self_subject: Subject(Message),
    /// Registry of room actors by name
    room_actors: Dict(String, Subject(room_actor.Message)),
    /// Path to save adjustments
    adjustments_path: String,
    /// Track previous adjustments to detect changes
    previous_adjustments: Dict(String, Float),
    /// Injectable timer function
    send_after: SendAfter(Message),
  )
}

/// Start the StateAggregatorActor without name registration (for testing)
/// Uses default persistence path
pub fn start_link() -> Result(Subject(Message), actor.StartError) {
  start_link_with_persistence(room_adjustments.default_path)
}

/// Start the StateAggregatorActor with persistence path
pub fn start_link_with_persistence(
  adjustments_path: String,
) -> Result(Subject(Message), actor.StartError) {
  start_link_with_options(
    adjustments_path: adjustments_path,
    send_after: timer.real_send_after,
  )
}

/// Start the StateAggregatorActor with all options (for testing)
/// Allows injection of send_after for deterministic timer testing
pub fn start_link_with_options(
  adjustments_path adjustments_path: String,
  send_after send_after: SendAfter(Message),
) -> Result(Subject(Message), actor.StartError) {
  actor.new_with_initialiser(1000, fn(self_subject) {
    actor.initialised(State(
      current: state.empty_deep_heating_state(),
      subscribers: [],
      broadcast_pending: False,
      self_subject: self_subject,
      room_actors: dict.new(),
      adjustments_path: adjustments_path,
      previous_adjustments: dict.new(),
      send_after: send_after,
    ))
    |> actor.returning(self_subject)
    |> Ok
  })
  |> actor.on_message(handle_message)
  |> actor.start
  |> extract_subject
}

/// Start the StateAggregatorActor and register it with the given name
pub fn start(
  name: Name(Message),
  adjustments_path: String,
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  start_with_options(
    name: name,
    adjustments_path: adjustments_path,
    send_after: timer.real_send_after,
  )
}

/// Start the StateAggregatorActor with a name and all options (for testing)
/// Allows injection of send_after for deterministic timer testing
pub fn start_with_options(
  name name: Name(Message),
  adjustments_path adjustments_path: String,
  send_after send_after: SendAfter(Message),
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  actor.new_with_initialiser(1000, fn(self_subject) {
    actor.initialised(State(
      current: state.empty_deep_heating_state(),
      subscribers: [],
      broadcast_pending: False,
      self_subject: self_subject,
      room_actors: dict.new(),
      adjustments_path: adjustments_path,
      previous_adjustments: dict.new(),
      send_after: send_after,
    ))
    |> actor.returning(self_subject)
    |> Ok
  })
  |> actor.on_message(handle_message)
  |> actor.named(name)
  |> actor.start
}

/// Create a child specification for supervision
pub fn child_spec(
  name: Name(Message),
  adjustments_path: String,
) -> supervision.ChildSpecification(Subject(Message)) {
  child_spec_with_options(name, adjustments_path, timer.real_send_after)
}

/// Create a child specification for supervision with injectable timer
pub fn child_spec_with_options(
  name: Name(Message),
  adjustments_path: String,
  send_after: SendAfter(Message),
) -> supervision.ChildSpecification(Subject(Message)) {
  supervision.worker(fn() {
    start_with_options(
      name: name,
      adjustments_path: adjustments_path,
      send_after: send_after,
    )
  })
}

fn handle_message(
  actor_state: State,
  message: Message,
) -> actor.Next(State, Message) {
  case message {
    GetState(reply_to) -> {
      process.send(reply_to, actor_state.current)
      actor.continue(actor_state)
    }
    Subscribe(subscriber) -> {
      actor.continue(
        State(..actor_state, subscribers: [
          subscriber,
          ..actor_state.subscribers
        ]),
      )
    }
    Unsubscribe(subscriber) -> {
      let new_subscribers =
        list.filter(actor_state.subscribers, fn(s) { s != subscriber })
      actor.continue(State(..actor_state, subscribers: new_subscribers))
    }
    RoomUpdated(name, room_state) -> {
      let new_current = update_room(actor_state.current, name, room_state)

      // Check if adjustment changed and persist if needed
      let previous_adjustment = dict.get(actor_state.previous_adjustments, name)
      let adjustment_changed = case previous_adjustment {
        Ok(prev) -> prev != room_state.adjustment
        Error(_) -> True
        // First update for this room
      }

      // Update previous adjustments
      let new_previous =
        dict.insert(
          actor_state.previous_adjustments,
          name,
          room_state.adjustment,
        )

      // Persist if adjustment changed
      case adjustment_changed {
        True -> {
          // Build list of all current adjustments
          let adjustments =
            list.map(new_current.rooms, fn(r) {
              room_adjustments.RoomAdjustment(
                room_name: r.name,
                adjustment: r.adjustment,
              )
            })
          // Save (ignore errors for now - we don't want to crash on I/O failure)
          let _ =
            room_adjustments.save(actor_state.adjustments_path, adjustments)
          Nil
        }
        False -> Nil
      }

      let new_state =
        State(
          ..actor_state,
          current: new_current,
          previous_adjustments: new_previous,
        )
      schedule_broadcast_if_needed(new_state)
    }
    Broadcast -> {
      // Broadcast to all subscribers
      list.each(actor_state.subscribers, fn(subscriber) {
        process.send(subscriber, actor_state.current)
      })
      actor.continue(State(..actor_state, broadcast_pending: False))
    }
    RegisterRoomActor(name, room_actor_subject) -> {
      let new_room_actors =
        dict.insert(actor_state.room_actors, name, room_actor_subject)
      actor.continue(State(..actor_state, room_actors: new_room_actors))
    }
    AdjustRoom(name, adjustment) -> {
      // Look up the room actor and forward the adjustment
      case dict.get(actor_state.room_actors, name) {
        Ok(room_actor_subject) -> {
          process.send(
            room_actor_subject,
            room_actor.AdjustmentChanged(adjustment),
          )
        }
        Error(_) -> {
          // Room not registered, silently ignore
          Nil
        }
      }
      actor.continue(actor_state)
    }
  }
}

fn update_room(
  deep_state: DeepHeatingState,
  name: String,
  room_state: RoomState,
) -> DeepHeatingState {
  // Check if room already exists
  let room_exists = list.any(deep_state.rooms, fn(r) { r.name == name })

  let new_rooms = case room_exists {
    True -> {
      // Update existing room
      list.map(deep_state.rooms, fn(r) {
        case r.name == name {
          True -> room_state
          False -> r
        }
      })
    }
    False -> {
      // Add new room
      [room_state, ..deep_state.rooms]
    }
  }

  state.DeepHeatingState(..deep_state, rooms: new_rooms)
}

fn schedule_broadcast_if_needed(
  actor_state: State,
) -> actor.Next(State, Message) {
  case actor_state.broadcast_pending {
    True -> {
      // Already have a broadcast pending, just continue
      actor.continue(actor_state)
    }
    False -> {
      // Schedule a broadcast after throttle period
      let _ =
        actor_state.send_after(actor_state.self_subject, throttle_ms, Broadcast)
      actor.continue(State(..actor_state, broadcast_pending: True))
    }
  }
}

fn extract_subject(
  result: Result(actor.Started(Subject(Message)), actor.StartError),
) -> Result(Subject(Message), actor.StartError) {
  case result {
    Ok(started) -> Ok(started.data)
    Error(e) -> Error(e)
  }
}
