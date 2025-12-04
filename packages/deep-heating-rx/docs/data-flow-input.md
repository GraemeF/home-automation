# Input Processing (Layers 1-4)

[Back to Overview](../DATA-FLOW.md)

This diagram shows how external data enters the system and is extracted into typed streams.

## Data Flow

```mermaid
flowchart TB
    subgraph External["External Data Sources"]
        HA[("Home Assistant")]
        User[("User Commands")]
        Timer60["Timer 60s"]
        Timer63["Timer 63s"]
    end

    subgraph Layer1["Layer 1: Raw Data Extraction"]
        direction LR
        TempSensor["temperatureSensorUpdate$"]
        TrvApi["trvApiUpdates$"]
        HeatingApi["heatingApiUpdates$"]
        ButtonEvents["buttonEvents$"]
    end

    subgraph Layer2["Layer 2: Configuration"]
        direction LR
        Rooms["rooms$"]
        RoomSensors["roomSensors$"]
        RoomTrvs["roomTrvs$"]
    end

    subgraph Layer3["Layer 3: Device State"]
        direction LR
        TrvTemps["trvTemperatures$"]
        TrvSchedules["trvHiveHeatingSchedules$"]
    end

    subgraph Layer4["Layer 4: State Subjects"]
        direction LR
        TrvControl[["trvControlStateSubject"]]
        TrvStatus[["trvStatusSubject"]]
        HeatingStatus[["heatingStatusSubject"]]
    end

    %% External to Layer 1
    HA --> TempSensor
    HA --> TrvApi
    HA --> HeatingApi
    HA --> ButtonEvents

    %% Layer 1 to Layer 2
    TrvApi --> Rooms

    %% Layer 2 internal
    Rooms --> RoomSensors
    Rooms --> RoomTrvs

    %% Layer 1 to Layer 3
    TrvApi --> TrvTemps
    TrvApi --> TrvSchedules

    %% Layer 1 to Layer 4
    TrvApi --> TrvControl
    TrvApi --> TrvStatus
    HeatingApi --> HeatingStatus

    %% Styling
    classDef external fill:#99ff99,stroke:#00cc00
    classDef subject fill:#ff9999,stroke:#cc0000
    classDef timer fill:#99ccff,stroke:#0066cc

    class HA,User external
    class Timer60,Timer63 timer
    class TrvControl,TrvStatus,HeatingStatus subject
```

## Stream Descriptions

### Layer 1: Raw Data Extraction

| Stream                     | Type                      | Description                                |
| -------------------------- | ------------------------- | ------------------------------------------ |
| `temperatureSensorUpdate$` | `TemperatureSensorEntity` | Temperature readings from external sensors |
| `trvApiUpdates$`           | `TrvUpdate`               | All TRV state changes from Home Assistant  |
| `heatingApiUpdates$`       | `HeatingUpdate`           | Main heating system state                  |
| `buttonEvents$`            | `GoodnightEventEntity`    | Goodnight button press events              |

### Layer 2: Configuration

| Stream         | Type                        | Description                             |
| -------------- | --------------------------- | --------------------------------------- |
| `rooms$`       | `Room[]`                    | Static room configuration               |
| `roomSensors$` | `Map<RoomName, SensorId[]>` | Maps rooms to their temperature sensors |
| `roomTrvs$`    | `Map<RoomName, TrvId[]>`    | Maps rooms to their TRVs                |

### Layer 3: Device State

| Stream                     | Type                                     | Description                         |
| -------------------------- | ---------------------------------------- | ----------------------------------- |
| `trvTemperatures$`         | `GroupedObservable<TrvId, number>`       | Current temperature reading per TRV |
| `trvHiveHeatingSchedules$` | `GroupedObservable<TrvId, WeekSchedule>` | Heating schedule per TRV            |

### Layer 4: State Subjects (Feedback Points)

These are `BehaviorSubject` instances that allow feedback loops:

| Subject                  | Type              | Description                                    |
| ------------------------ | ----------------- | ---------------------------------------------- |
| `trvControlStateSubject` | `TrvControlState` | Current mode (heat/off) and target temperature |
| `trvStatusSubject`       | `TrvStatus`       | Whether TRV is actively heating                |
| `heatingStatusSubject`   | `HeatingStatus`   | Whether main boiler is on                      |

## Key Files

- `src/lib/streams/homeAssistant/` - Layer 1 extractors
- `src/lib/streams/rooms.ts` - Layer 2 configuration
- `src/lib/streams/trvs/` - Layer 3 & 4 TRV state
