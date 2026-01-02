# Deep Heating: Gleam Actor Architecture

## Supervision Tree

```
DeepHeatingSupervisor
├── HomeAssistantSupervisor
│   ├── HaPollerActor          (polls HA API every 5s)
│   └── HaCommandActor         (sends setTemperature/setHvacMode)
│
├── HouseModeActor             (singleton - tracks Auto/Sleeping)
│
├── RoomsSupervisor
│   ├── RoomSupervisor(lounge)
│   │   ├── RoomActor(lounge)
│   │   ├── TrvActor(lounge_trv)
│   │   └── RoomDecisionActor(lounge)
│   │
│   ├── RoomSupervisor(bedroom)
│   │   ├── RoomActor(bedroom)
│   │   ├── TrvActor(bedroom_trv_1)
│   │   ├── TrvActor(bedroom_trv_2)
│   │   └── RoomDecisionActor(bedroom)
│   │
│   └── ... (one supervisor per room)
│
├── StateAggregatorActor       (collects snapshots for UI)
│
└── WebSocketSupervisor
    ├── WebSocketListenerActor
    ├── ClientActor(conn_1)
    ├── ClientActor(conn_2)
    └── ...
```

## Message Types

```gleam
// From Home Assistant Poller
pub type TrvUpdate {
  TrvUpdate(
    entity_id: TrvEntityId,
    temperature: Option(Temperature),
    target: Option(Temperature),
    mode: HvacMode,
    is_heating: Bool,
  )
}

pub type HeatingUpdate {
  HeatingUpdate(is_heating: Bool)
}

pub type SleepButtonPressed

// Internal Actor Messages
pub type RoomActorMsg {
  TrvTemperatureChanged(trv_id: TrvEntityId, temp: Temperature)
  TrvTargetChanged(trv_id: TrvEntityId, target: Temperature)
  TrvModeChanged(trv_id: TrvEntityId, mode: HvacMode)
  ExternalTempChanged(temp: Temperature)
  HouseModeChanged(mode: HouseMode)
  AdjustmentChanged(delta: Int)
  GetState(reply_to: Subject(RoomState))
}

pub type TrvActorMsg {
  Update(TrvUpdate)
  SetTarget(Temperature)
  SetMode(HvacMode)
  GetState(reply_to: Subject(TrvState))
}

pub type RoomDecisionMsg {
  RoomStateChanged(RoomState)
  TrvStateChanged(trv_id: TrvEntityId, TrvState)
  Evaluate
}

pub type HouseModeMsg {
  SleepButtonPressed
  WakeUp
  GetMode(reply_to: Subject(HouseMode))
}

// Commands to Home Assistant
pub type HaCommand {
  SetTrvTarget(entity_id: TrvEntityId, target: Temperature)
  SetTrvMode(entity_id: TrvEntityId, mode: HvacMode)
}

// WebSocket Messages
pub type ClientToServer {
  AdjustRoom(room_name: String, delta: Int)
}

pub type ServerToClient {
  StateSnapshot(DeepHeatingState)
}
```

## Core Actor Implementations

### TrvActor

Holds the latest state from HA and notifies parent room.

```gleam
pub type TrvState {
  TrvState(
    entity_id: TrvEntityId,
    temperature: Option(Temperature),
    target: Option(Temperature),
    mode: HvacMode,
    is_heating: Bool,
  )
}

pub fn trv_actor(
  entity_id: TrvEntityId,
  room_actor: Subject(RoomActorMsg),
  ha_commands: Subject(HaCommand),
) -> Result(Subject(TrvActorMsg), StartError) {
  actor.start(TrvState(entity_id, None, None, Off, False), fn(msg, state) {
    case msg {
      Update(update) -> {
        let new_state = TrvState(
          entity_id: entity_id,
          temperature: update.temperature,
          target: update.target,
          mode: update.mode,
          is_heating: update.is_heating,
        )
        // Notify room actor of changes
        case state.temperature != new_state.temperature {
          True -> process.send(room_actor, TrvTemperatureChanged(entity_id, new_state.temperature))
          False -> Nil
        }
        actor.continue(new_state)
      }
      SetTarget(temp) -> {
        process.send(ha_commands, SetTrvTarget(entity_id, temp))
        actor.continue(state)
      }
      GetState(reply_to) -> {
        process.send(reply_to, state)
        actor.continue(state)
      }
    }
  })
}
```

### RoomActor

Aggregates TRV states + external sensor + house mode + adjustments.

```gleam
pub type RoomState {
  RoomState(
    name: RoomName,
    schedule: Schedule,
    temperature: Option(Temperature),
    target: Option(Temperature),
    adjustment: Int,
    house_mode: HouseMode,
    trv_states: Dict(TrvEntityId, TrvState),
  )
}

fn recompute_target(state: RoomState) -> RoomState {
  let scheduled = get_scheduled_temp(state.schedule, now())
  let target = case state.house_mode {
    Sleeping -> min_room_temp
    Off -> min_trv_temp
    Auto -> clamp(scheduled + float(state.adjustment), min_room_temp, max_room_temp)
  }
  RoomState(..state, target: Some(target))
}
```

### RoomDecisionActor

Decides what to tell the TRVs based on room state.

```gleam
fn compute_desired_trv_target(
  room: RoomState,
  trv: TrvState,
  room_target: Temperature,
) -> Temperature {
  case room.temperature {
    None -> room_target
    Some(room_temp) -> {
      let diff = room_target - room_temp
      case diff {
        d if d > 0.5 -> room_target + 2.0   // Room cold, push TRV up
        d if d < -0.5 -> room_target - 1.0  // Room hot, back off
        _ -> room_target                     // Room at target
      }
    }
  }
}
```

## Data Flow Example

```
User presses "Goodnight" button in Home Assistant
    │
    ▼
HaPollerActor detects event.goodnight fired
    │
    ▼
HaPollerActor sends SleepButtonPressed to HouseModeActor
    │
    ▼
HouseModeActor updates state to Sleeping
HouseModeActor broadcasts HouseModeChanged(Sleeping) to all RoomActors
    │
    ▼
RoomActor(lounge) receives HouseModeChanged(Sleeping)
RoomActor(lounge) recomputes target → 16°C (min)
RoomActor(lounge) sends RoomStateChanged to RoomDecisionActor(lounge)
    │
    ▼
RoomDecisionActor(lounge) evaluates: target changed from 20°C to 16°C
RoomDecisionActor(lounge) sends SetTarget(16) to TrvActor(lounge_trv)
    │
    ▼
TrvActor(lounge_trv) sends SetTrvTarget to HaCommandActor
    │
    ▼
HaCommandActor calls Home Assistant API: climate.set_temperature(lounge_trv, 16)
```

## Comparison: RxJS vs Actors

### RxJS Version (current)
```typescript
export const roomTargetTemperatures$ = (
  roomScheduledTargetTemperatures$,
  roomModes$,
  roomAdjustments$
) =>
  combineLatest([...]).pipe(
    groupBy(...), mergeMap(...), shareReplayLatestDistinct(),
    filter(Either.isRight), shareReplayLatestDistinctByKey(...)
  );
```

### Gleam Actor Version
```gleam
fn recompute_target(state: RoomState) -> RoomState {
  let scheduled = get_scheduled_temp(state.schedule, now())
  let target = case state.house_mode {
    Sleeping -> min_room_temp
    Off -> min_trv_temp
    Auto -> clamp(scheduled + float(state.adjustment), min, max)
  }
  RoomState(..state, target: Some(target))
}
```

The actor version:
- No subscription management
- No `shareReplay` hacks
- No `combineLatest` timing issues
- State is explicit and inspectable
- Testing is trivial (send message, check state)

## What We'd Gain

1. **Debuggability**: Can query any actor's state at any time
2. **Testability**: Pure functions + message passing = easy unit tests
3. **Fault tolerance**: Supervisor restarts crashed actors
4. **Observability**: OTP gives us process inspection for free
5. **Simplicity**: Each actor does one thing

## What We'd Lose

1. **TypeScript ecosystem**: Effect, RxJS tooling, npm packages
2. **SvelteKit**: Would need Lustre or keep frontend separate
3. **Team familiarity**: Gleam/BEAM is different from JS/TS
