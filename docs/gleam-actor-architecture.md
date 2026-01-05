# Deep Heating: Gleam Actor Architecture

This document describes the actor-based architecture of Deep Heating, a Gleam application running on the BEAM (Erlang runtime). The architecture follows a **Ports and Adapters** (Hexagonal) pattern with OTP supervision for fault tolerance.

## Supervision Tree

```
DeepHeatingSupervisor
├── HaPollerActor            (polls HA API every 5s)
├── HaCommandActor           (sends setTemperature/setHvacMode, debounced)
├── EventRouterActor         (routes HA events to correct actors)
├── HouseModeActor           (tracks Auto/Sleeping mode)
├── HeatingControlActor      (aggregates room demand, controls boiler)
├── BoilerCommandAdapterActor (domain → HA for boiler commands)
├── StateAggregatorActor     (collects snapshots for UI)
│
└── RoomsSupervisor
    ├── RoomSupervisor(lounge)
    │   ├── RoomActor(lounge)              (aggregates room state)
    │   ├── TrvActor(lounge_trv)           (holds TRV state)
    │   ├── RoomDecisionActor(lounge)      (computes TRV targets)
    │   └── TrvCommandAdapterActor(lounge) (domain → HA for TRV commands)
    │
    ├── RoomSupervisor(bedroom)
    │   ├── RoomActor(bedroom)
    │   ├── TrvActor(bedroom_trv_1)
    │   ├── TrvActor(bedroom_trv_2)
    │   ├── RoomDecisionActor(bedroom)
    │   └── TrvCommandAdapterActor(bedroom)
    │
    └── ... (one supervisor per room)
```

Key architectural decisions:
- **Per-room supervision**: Each room has its own supervisor with restart strategy
- **Adapter actors**: Domain commands (TrvCommand, BoilerCommand) are translated to HA commands by dedicated adapter actors
- **Name-based lookups**: Actors find each other by OTP name registry, surviving supervisor restarts

## Message Types

### TRV Layer

```gleam
// From Home Assistant Poller (infrastructure)
pub type TrvUpdate {
  TrvUpdate(
    temperature: Option(Temperature),
    target: Option(Temperature),
    mode: HvacMode,
    is_heating: Bool,
  )
}

// TrvActor messages
pub type trv_actor.Message {
  GetState(reply_to: Subject(TrvState))
  Update(TrvUpdate)
}

// Domain command from RoomDecisionActor
pub type TrvCommand {
  TrvCommand(entity_id: ClimateEntityId, mode: HvacMode, target: Temperature)
}
```

### Room Layer

```gleam
// RoomActor messages
pub type room_actor.Message {
  GetState(reply_to: Subject(RoomState))
  TrvTemperatureChanged(entity_id: ClimateEntityId, temperature: Temperature)
  TrvTargetChanged(entity_id: ClimateEntityId, target: Temperature)
  TrvModeChanged(entity_id: ClimateEntityId, mode: HvacMode)
  TrvIsHeatingChanged(entity_id: ClimateEntityId, is_heating: Bool)
  HouseModeChanged(mode: HouseMode)
  AdjustmentChanged(adjustment: Float)
  ExternalTempChanged(temperature: Temperature)
  ReComputeTarget  // Internal timer message
}

// RoomDecisionActor messages
pub type room_decision_actor.Message {
  RoomStateChanged(room_actor.RoomState)
}
```

### House-Wide Layer

```gleam
// HouseModeActor messages
pub type house_mode_actor.Message {
  GetMode(reply_to: Subject(HouseMode))
  SleepButtonPressed
  WakeUp
  RegisterRoomActor(room_actor: Subject(room_actor.Message))
  ReEvaluateMode  // Internal timer message
}

// HeatingControlActor messages
pub type heating_control_actor.Message {
  GetState(reply_to: Subject(HeatingControlState))
  RoomUpdated(name: String, room_state: room_actor.RoomState)
  BoilerStatusChanged(is_heating: Bool)
}

// Domain command from HeatingControlActor
pub type BoilerCommand {
  BoilerCommand(entity_id: ClimateEntityId, mode: HvacMode, target: Temperature)
}
```

### Infrastructure Layer

```gleam
// HaPollerActor events (to EventRouterActor)
pub type PollerEvent {
  TrvUpdated(entity_id: ClimateEntityId, update: TrvUpdate)
  SensorUpdated(entity_id: SensorEntityId, temperature: Option(Temperature))
  HeatingStatusChanged(is_heating: Bool)
  SleepButtonPressed
  PollingStarted
  PollingStopped
  PollCompleted(duration_ms: Int)
  PollFailed(reason: HaError)
  BackoffApplied(seconds: Int)
  BackoffReset
}

// HaCommandActor messages
pub type ha_command_actor.Message {
  SetTrvAction(entity_id: ClimateEntityId, mode: HvacMode, target: Temperature)
  SetHeatingAction(entity_id: ClimateEntityId, mode: HvacMode, target: Temperature)
  TrvDebounceTimeout(entity_id: ClimateEntityId)   // Internal
  HeatingDebounceTimeout                            // Internal
}
```

## Core Actor Implementations

### TrvActor

Holds the latest state from HA and notifies parent RoomActor on changes.

```gleam
pub type TrvState {
  TrvState(
    temperature: Option(Temperature),
    target: Option(Temperature),
    mode: HvacMode,
    is_heating: Bool,
  )
}

// TrvActor notifies RoomActor via name lookup (survives restarts)
fn handle_message(state: State, message: Message) -> actor.Next(State) {
  case message {
    Update(update) -> {
      let new_trv = apply_update(state.trv, update)

      // Notify room of any changes
      case state.trv.temperature != new_trv.temperature {
        True -> send_to_room(state.room_actor_name,
          TrvTemperatureChanged(state.entity_id, update.temperature))
        False -> Nil
      }
      // ... similar for target, mode, is_heating

      actor.continue(State(..state, trv: new_trv))
    }
    GetState(reply_to) -> {
      process.send(reply_to, state.trv)
      actor.continue(state)
    }
  }
}
```

### RoomActor

Aggregates TRV states + external sensor + house mode + adjustments.

```gleam
pub type RoomState {
  RoomState(
    name: String,
    temperature: Option(Temperature),           // From external sensor
    target_temperature: Option(Temperature),    // Computed from schedule + adjustment
    house_mode: HouseMode,
    room_mode: RoomMode,                        // Derived from TRVs + house mode
    adjustment: Float,                          // User adjustment (+/- degrees)
    trv_states: Dict(ClimateEntityId, TrvState),
  )
}

/// Pure function: compute target from schedule, mode, and adjustment
pub fn compute_target_temperature(
  weekday: Weekday,
  time: TimeOfDay,
  schedule: WeekSchedule,
  house_mode: HouseMode,
  adjustment: Float,
) -> Temperature {
  case house_mode {
    HouseModeSleeping -> temperature.min_room_target
    HouseModeAuto -> {
      let scheduled = schedule.get_temperature_for(schedule, weekday, time)
      temperature.clamp_room_target(scheduled |> temperature.add(adjustment))
    }
  }
}
```

### RoomDecisionActor

Computes desired TRV targets using offset compensation algorithm.

```gleam
/// Pure function: compute TRV target using offset compensation
/// trvTarget = roomTarget + (trvTemp - roomTemp)
/// Clamped to safe TRV command range (7-32°C)
fn compute_desired_trv_target(
  room_target: Temperature,
  room_temp: Option(Temperature),
  trv_temp: Option(Temperature),
) -> Temperature {
  case room_temp, trv_temp {
    Some(room), Some(trv) -> {
      let offset = temperature.subtract(trv, room)
      room_target
      |> temperature.add_float(offset)
      |> temperature.clamp_trv_command_target
    }
    _, _ -> room_target |> temperature.clamp_trv_command_target
  }
}
```

## Data Flow Example

```
User presses "Goodnight" button in Home Assistant
    │
    ▼
HaPollerActor detects input_boolean.goodnight state change
    │
    ▼
HaPollerActor emits PollerEvent.SleepButtonPressed
    │
    ▼
EventRouterActor receives event, sends to HouseModeActor
    │
    ▼
HouseModeActor updates state to Sleeping
HouseModeActor broadcasts HouseModeChanged(Sleeping) to all registered RoomActors
    │
    ▼
RoomActor(lounge) receives HouseModeChanged(Sleeping)
RoomActor recomputes target → 16°C (min_room_target)
RoomActor notifies RoomDecisionActor via name lookup
    │
    ▼
RoomDecisionActor(lounge) receives RoomStateChanged
RoomDecisionActor computes TRV target with offset compensation
RoomDecisionActor sends TrvCommand to TrvCommandAdapterActor via name lookup
    │
    ▼
TrvCommandAdapterActor(lounge) receives TrvCommand (domain)
TrvCommandAdapterActor converts to ha_command_actor.SetTrvAction (infrastructure)
TrvCommandAdapterActor sends to HaCommandActor via name lookup
    │
    ▼
HaCommandActor queues command with 5s debounce
HaCommandActor calls HA API: climate.set_temperature(lounge_trv, target)
                            climate.set_hvac_mode(lounge_trv, heat)
```

## Ports and Adapters Pattern

The architecture cleanly separates domain logic from infrastructure:

### Domain Layer (Pure)
- `RoomActor`: Room state aggregation, schedule evaluation
- `RoomDecisionActor`: TRV target computation with offset compensation
- `HeatingControlActor`: Boiler demand aggregation
- `HouseModeActor`: Mode transitions based on time and user input
- Domain commands: `TrvCommand`, `BoilerCommand`

### Infrastructure Layer
- `HaPollerActor`: Polls HA REST API, parses responses
- `HaCommandActor`: Sends commands to HA REST API with debouncing
- `EventRouterActor`: Routes poller events to correct actors via registries

### Adapter Actors
- `TrvCommandAdapterActor`: Converts `TrvCommand` → `SetTrvAction`
- `BoilerCommandAdapterActor`: Converts `BoilerCommand` → `SetHeatingAction`

This separation means:
- Domain actors are testable without HTTP
- Infrastructure can be swapped (e.g., different HA API versions)
- Adapters handle the impedance mismatch

## Gleam OTP Patterns and Gotchas

### Subject Ownership (CRITICAL)

A `Subject` in Gleam OTP is tied to the process that created it. Messages sent to a Subject go to the **creating process's mailbox**, not to any process that happens to have a reference to it.

**Bug pattern (DON'T DO THIS):**
```gleam
// Parent creates Subject
let subject = process.new_subject()

// Parent spawns child, passes Subject
process.spawn_unlinked(fn() {
  // Child tries to receive - WILL NEVER WORK!
  // Messages go to parent's mailbox, not child's
  process.receive_forever(subject)
})
```

**Fix: Child creates its own Subject:**
```gleam
let response_subject = process.new_subject()

process.spawn_unlinked(fn() {
  // Child creates ITS OWN Subject
  let subject = process.new_subject()
  // Sends it back to parent
  process.send(response_subject, subject)
  // Now child CAN receive on its own Subject
  process.receive_forever(subject)
})

let assert Ok(child_subject) = process.receive(response_subject, 5000)
```

### Named Subjects and `actor.named()`

`process.named_subject(name)` only works for actors that use `actor.named(name)` during startup.

**Why it works:**
1. `actor.named(name)` registers the actor's PID with Erlang's name registry
2. The actor creates its Subject using `named_subject(name)` internally
3. The actor selects on that Subject
4. External callers using `named_subject(name)` get a Subject pointing to the same selector

**Actors using `actor.named()` for name-based lookups:**
- TrvActor ✓
- RoomActor ✓
- RoomDecisionActor ✓
- TrvCommandAdapterActor ✓
- HeatingControlActor ✓
- BoilerCommandAdapterActor ✓
- HaCommandActor ✓
- StateAggregatorActor ✓

**Other actors (capture Subject at startup via injection):**
- EventRouterActor
- HouseModeActor
- HaPollerActor

### Name-Based Lookups for Supervision Recovery

When actors are supervised with restart strategies, a crashed actor gets a **new Subject** after restart. If other actors hold references to the old Subject, messages will be lost.

**Solution: Store Names, lookup at message send time.**

```gleam
// WRONG: Storing Subject directly (breaks after restart)
type State {
  State(room_actor: Subject(RoomMessage))
}

fn notify_room(state: State, msg: RoomMessage) {
  process.send(state.room_actor, msg)  // Fails if room_actor restarted!
}
```

```gleam
// RIGHT: Store Name, lookup each time
type State {
  State(room_actor_name: Name(RoomMessage))
}

fn notify_room(state: State, msg: RoomMessage) {
  let subject = process.named_subject(state.room_actor_name)
  process.send(subject, msg)  // Always gets current actor's Subject
}
```

**Complete actor chain using name-based lookups:**
```
TrvActor → RoomActor (by name)
    ↓ triggers
RoomActor → RoomDecisionActor (by name)
    ↓ computes setpoint
RoomDecisionActor → TrvCommandAdapterActor (by name)
    ↓ translates domain → HA
TrvCommandAdapterActor → HaCommandActor (by name)
    ↓ sends to Home Assistant
HaCommandActor → Home Assistant API
```

**Restart test proving this works** (from `rooms_supervisor_test.gleam`):
```gleam
pub fn trv_actor_is_restarted_when_it_crashes_test() {
  // ... start room with TrvActor ...

  let original_pid = trv_ref.pid
  let trv_name = trv_ref.name

  // Verify it's alive
  let trv_subject = process.named_subject(trv_name)
  process.send(trv_subject, trv_actor.GetState(reply1))
  let assert Ok(_) = process.receive(reply1, 1000)

  // Kill it
  process.kill(original_pid)
  process.sleep(200)  // Wait for supervisor restart

  // Query again via same name - restarted actor responds!
  process.send(trv_subject, trv_actor.GetState(reply2))
  let result = process.receive(reply2, 1000)
  should.be_ok(result)  // Works because name lookup gets new Subject
}
```

### Adapter Actor Pattern

When you need an actor that receives one message type but converts to another (e.g., domain → infrastructure), use a custom selector:

```gleam
pub fn start(
  name: Name(TrvCommand),
  ha_command_actor_name: Name(ha_command_actor.Message),
) -> Result(actor.Started(Subject(TrvCommand)), actor.StartError) {
  actor.new_with_initialiser(5000, fn(_default_subject) {
    // Create Subject for the type we WANT to receive
    let trv_commands: Subject(TrvCommand) = process.new_subject()
    let initial_state = State(ha_command_actor_name: ha_command_actor_name)

    // Map incoming TrvCommand to our internal Message type
    let selector =
      process.new_selector()
      |> process.select_map(trv_commands, fn(cmd) { IncomingCommand(cmd) })

    actor.initialised(initial_state)
    |> actor.selecting(selector)
    |> actor.returning(trv_commands)  // Return the Subject callers should use
    |> Ok
  })
  |> actor.named(name)
  |> actor.on_message(handle_message)
  |> actor.start
}
```

This avoids raw `spawn_unlinked` + `receive_forever` which:
- Can't be supervised
- Don't handle OTP shutdown gracefully
- Cause test teardown issues

### Timer Patterns

For periodic re-evaluation (e.g., schedule-based target updates):

```gleam
fn start_recompute_timer() -> Nil {
  // 60 second timer for schedule-based re-evaluation
  process.send_after(process.new_subject(), 60_000, ReComputeTarget)
  |> fn(_) { Nil }
}

fn handle_message(state: State, message: Message) -> actor.Next(State) {
  case message {
    ReComputeTarget -> {
      let new_state = recompute_target(state)
      start_recompute_timer()  // Reschedule
      actor.continue(new_state)
    }
    // ...
  }
}
```
