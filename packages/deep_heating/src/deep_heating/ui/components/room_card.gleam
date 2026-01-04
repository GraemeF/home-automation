import deep_heating/state.{type RoomState, type TemperatureReading}
import deep_heating/temperature
import deep_heating/ui/components/room_controls
import deep_heating/ui/icons
import deep_heating/ui/msg.{type Msg}
import gleam/option.{type Option, None, Some}
import lustre/attribute.{attribute, class}
import lustre/element.{type Element, text}
import lustre/element/html.{div}

/// Room card component displaying room temperature and controls.
pub fn view(room: RoomState) -> Element(Msg) {
  let is_heating = is_room_heating(room)

  div(
    [
      class("card card-sm w-44 shadow-md " <> background_class(is_heating)),
      attribute("style", "color: white"),
      attribute("data-testid", "room-card"),
      attribute("data-room-name", room.name),
    ],
    [
      div([class("card-body p-3")], [
        header(room.name, is_heating),
        current_temperature(room.temperature),
        controls_section(room),
      ]),
    ],
  )
}

fn header(name: String, is_heating: Bool) -> Element(Msg) {
  div([class("card-title text-sm flex items-center gap-1")], [
    text(name),
    case is_heating {
      True -> icons.fire(icons.IconSmall)
      False -> element.none()
    },
  ])
}

fn current_temperature(reading: Option(TemperatureReading)) -> Element(Msg) {
  let display = case reading {
    Some(r) -> temperature.format(r.temperature)
    None -> "–"
  }

  div(
    [
      class("stat-value text-right text-2xl"),
      attribute("data-testid", "current-temp"),
    ],
    [text(display)],
  )
}

fn controls_section(room: RoomState) -> Element(Msg) {
  case room.target_temperature {
    Some(_) -> room_controls.view(room)
    None -> element.none()
  }
}

fn is_room_heating(room: RoomState) -> Bool {
  case room.is_heating {
    Some(True) -> True
    _ -> False
  }
}

/// Heating background color - matches TypeScript version's #FF9700 (orange)
const heating_bg = "bg-[#FF9700]"

/// Cooling background color - matches TypeScript version's #77DAE8 (blue)
const cooling_bg = "bg-[#77DAE8]"

fn background_class(is_heating: Bool) -> String {
  case is_heating {
    True -> heating_bg
    False -> cooling_bg
  }
}
