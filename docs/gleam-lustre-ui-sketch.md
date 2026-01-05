# Deep Heating: Lustre UI Sketch

> **Note**: This document was a planning sketch created during the Gleam port. The UI is now implemented in `packages/deep_heating/src/deep_heating/ui/`. The actual implementation follows this sketch closely, with some refinements made during development.
>
> **Actual implementation files:**
> - `ui/app.gleam` - Main application entry point
> - `ui/model.gleam` - Model types (matches sketch)
> - `ui/msg.gleam` - Message types
> - `ui/update.gleam` - Update function
> - `ui/view.gleam` - Main view composition
> - `ui/components/` - Room cards, controls, heating badge, connection overlay

---

## Original Planning Document

## Project Structure

```
deep_heating_ui/
├── gleam.toml
├── src/
│   ├── deep_heating_ui.gleam      # Main entry point
│   ├── model.gleam                # State types
│   ├── msg.gleam                  # Message types
│   ├── update.gleam               # State updates
│   ├── view.gleam                 # Main view
│   └── components/
│       ├── heating_badge.gleam
│       ├── room_card.gleam
│       └── room_controls.gleam
```

## Types (model.gleam)

```gleam
import gleam/option.{type Option}

pub type Temperature = Float

pub type RoomMode {
  Off
  Auto
  Sleeping
}

pub type TemperatureReading {
  TemperatureReading(temperature: Temperature, time: Int)
}

pub type RoomState {
  RoomState(
    name: String,
    temperature: Option(TemperatureReading),
    target_temperature: Option(Temperature),
    radiators: List(RadiatorState),
    mode: Option(RoomMode),
    is_heating: Option(Bool),
    adjustment: Float,
  )
}

pub type DeepHeatingState {
  DeepHeatingState(rooms: List(RoomState), is_heating: Option(Bool))
}

pub type Model {
  Model(connected: Bool, state: Option(DeepHeatingState))
}

pub fn init(_flags) -> Model {
  Model(connected: False, state: option.None)
}
```

## Messages (msg.gleam)

```gleam
pub type Msg {
  Connected
  Disconnected
  StateReceived(DeepHeatingState)
  AdjustRoom(room_name: String, delta: Float)
}
```

## Room Card Component

```gleam
import gleam/option.{type Option, None, Some}
import lustre/attribute.{class, style}
import lustre/element.{type Element, text}
import lustre/element/html.{div, p}
import model.{type RoomState}
import msg.{type Msg}
import components/room_controls

pub fn view(room: RoomState) -> Element(Msg) {
  let is_heating = case room.is_heating {
    Some(True) -> True
    _ -> False
  }

  let card_class = case is_heating {
    True -> "card card-sm w-44 bg-heating"
    False -> "card card-sm w-44 bg-cooling"
  }

  div([class(card_class), style([#("color", "white")])], [
    div([class("card-body")], [
      // Header: room name + fire icon
      div([class("card-title")], [
        text(room.name),
        case is_heating {
          True -> fire_icon()
          False -> element.none()
        },
      ]),
      // Current temperature
      div([class("stat-value text-right")], [
        text(format_temperature(room.temperature)),
      ]),
      // Controls (if has target)
      case room.target_temperature {
        Some(_) -> room_controls.view(room)
        None -> element.none()
      },
    ]),
  ])
}

fn format_temperature(reading: Option(TemperatureReading)) -> String {
  case reading {
    None -> "—"
    Some(r) -> float.to_string(r.temperature) <> "°"
  }
}
```

## Room Controls Component

```gleam
import lustre/event.{on_click}
import msg.{type Msg, AdjustRoom}

const step = 0.5

pub fn view(room: RoomState) -> Element(Msg) {
  let is_auto = case room.mode {
    Some(Auto) -> True
    _ -> False
  }

  div([class("flex items-center gap-2")], [
    case is_auto {
      True -> colder_button(room.name, room.adjustment)
      False -> element.none()
    },
    target_display(room.target_temperature, room.adjustment),
    case is_auto {
      True -> warmer_button(room.name, room.adjustment)
      False -> element.none()
    },
  ])
}

fn colder_button(room_name: String, adjustment: Float) -> Element(Msg) {
  button(
    [
      class("btn btn-circle btn-ghost btn-sm"),
      on_click(AdjustRoom(room_name, adjustment -. step)),
    ],
    [minus_icon(adjustment <. 0.0)],
  )
}

fn warmer_button(room_name: String, adjustment: Float) -> Element(Msg) {
  button(
    [
      class("btn btn-circle btn-ghost btn-sm"),
      on_click(AdjustRoom(room_name, adjustment +. step)),
    ],
    [plus_icon(adjustment >. 0.0)],
  )
}
```

## Main View

```gleam
import gleam/list
import gleam/option.{None, Some}
import lustre/attribute.{class}
import lustre/element.{type Element, text}
import lustre/element/html.{div, ul, li, a}
import components/heating_badge
import components/room_card

pub fn view(model: Model) -> Element(Msg) {
  div([], [
    breadcrumbs(),
    case model.state {
      None -> loading()
      Some(state) -> home_view(state)
    },
  ])
}

fn home_view(state: DeepHeatingState) -> Element(Msg) {
  div([class("mx-3.5")], [
    div([class("flex flex-row justify-between items-center")], [
      heating_badge.view(state.is_heating),
    ]),
    div(
      [class("flex flex-row flex-wrap gap-2")],
      state.rooms
        |> sort_by_temperature
        |> list.map(room_card.view),
    ),
  ])
}
```

## Server Component Architecture

With Lustre Server Components, the architecture becomes simpler - the client just receives DOM patches:

```gleam
// server.gleam - runs on BEAM
import lustre
import lustre/server_component

pub fn start_server_component(
  state_actor: Subject(StateRequest),
) -> Result(Subject(Msg), StartError) {
  lustre.server_component(init, update, view)
  |> lustre.start_server_component()
}
```

The beauty here is:
1. **No separate API** - UI and backend share the same runtime
2. **No serialization** - state is directly accessible
3. **Automatic sync** - Lustre handles WebSocket patches

## Comparison: SvelteKit vs Lustre

### SvelteKit (Current)
```svelte
<script lang="ts">
  import { apiClientStore } from '$lib/stores/apiClient';
  import type { RoomState } from '@home-automation/deep-heating-types';
  import { Option, pipe } from 'effect';

  const isHeating = $derived(
    pipe(room.isHeating, Option.getOrElse(() => false))
  );
</script>

<div class="card" class:bg-heating={isHeating}>
  <!-- template -->
</div>
```

### Lustre (Proposed)
```gleam
pub fn view(room: RoomState) -> Element(Msg) {
  let is_heating = option.unwrap(room.is_heating, False)
  div([class(card_class(is_heating))], [
    div([class("card-body")], [
      header(room.name, is_heating),
      temperature_display(room.temperature),
      controls(room),
    ]),
  ])
}
```

**Key differences:**
- No reactive primitives (`$derived`, `pipe`, `Option.getOrElse`)
- No store subscriptions
- No `class:` directive magic - just functions
- Pattern matching instead of ternaries
- Type-safe by default

## What We'd Gain / What We'd Lose

> **Note**: These trade-off sections were written before implementation. The Gleam port is now complete and we can confirm:
>
> **Confirmed gains:**
> - Single language (Gleam everywhere) ✓
> - Type safety (no runtime type errors) ✓
> - Simpler mental model (MVU pattern) ✓
> - No build complexity (just `gleam build`) ✓
>
> **Confirmed trade-offs:**
> - Tailwind/DaisyUI bundled locally (works well)
> - Hot reloading not as polished (acceptable)
> - Fewer off-the-shelf components (we built what we needed)
