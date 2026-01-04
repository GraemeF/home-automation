import deep_heating/mode.{RoomModeAuto}
import deep_heating/state.{type RoomState}
import deep_heating/temperature.{type Temperature}
import deep_heating/ui/icons.{IconMedium}
import deep_heating/ui/msg.{type Msg, AdjustRoom}
import gleam/float
import gleam/int
import gleam/option.{type Option, None, Some}
import lustre/attribute.{attribute, class}
import lustre/element.{type Element, text}
import lustre/element/html.{button, div, span}
import lustre/event

const step: Float = 0.5

/// Room temperature adjustment controls.
/// Shows target temperature with optional adjustment badge.
/// In Auto mode, also shows +/- buttons for temperature adjustment.
pub fn view(room: RoomState) -> Element(Msg) {
  let is_auto = is_auto_mode(room)

  div(
    [
      class("card-actions text-xs flex items-center gap-0"),
      attribute("data-testid", "room-controls"),
    ],
    [
      case is_auto {
        True -> colder_button(room.name, room.adjustment)
        False -> element.none()
      },
      target_display(room.target_temperature, room.adjustment),
      case is_auto {
        True -> warmer_button(room.name, room.adjustment)
        False -> element.none()
      },
    ],
  )
}

fn colder_button(room_name: String, adjustment: Float) -> Element(Msg) {
  button(
    [
      class("btn btn-circle btn-ghost btn-sm"),
      attribute("data-testid", "colder-button"),
      event.on_click(AdjustRoom(room_name, adjustment -. step)),
    ],
    [icons.minus_icon(adjustment <. 0.0, IconMedium)],
  )
}

fn warmer_button(room_name: String, adjustment: Float) -> Element(Msg) {
  button(
    [
      class("btn btn-circle btn-ghost btn-sm"),
      attribute("data-testid", "warmer-button"),
      event.on_click(AdjustRoom(room_name, adjustment +. step)),
    ],
    [icons.plus_icon(adjustment >. 0.0, IconMedium)],
  )
}

fn target_display(
  target: Option(Temperature),
  adjustment: Float,
) -> Element(Msg) {
  span(
    [class("flex-1 text-center"), attribute("data-testid", "target-display")],
    [
      text(format_target(target)),
      case adjustment != 0.0 {
        True -> adjustment_badge(adjustment)
        False -> element.none()
      },
    ],
  )
}

fn format_target(target: Option(Temperature)) -> String {
  case target {
    Some(t) -> temperature.format_bare(t)
    None -> "–"
  }
}

fn adjustment_badge(adjustment: Float) -> Element(Msg) {
  let sign = case adjustment >. 0.0 {
    True -> "+"
    False -> ""
  }
  span(
    [
      class("text-xs opacity-75 ml-1"),
      attribute("data-testid", "adjustment-badge"),
    ],
    [text("(" <> sign <> float_to_1dp(adjustment) <> "°C)")],
  )
}

fn is_auto_mode(room: RoomState) -> Bool {
  case room.mode {
    Some(RoomModeAuto) -> True
    _ -> False
  }
}

/// Format a float to 1 decimal place, preserving sign.
fn float_to_1dp(value: Float) -> String {
  let abs_value = float.absolute_value(value)
  let rounded = int.to_float(float.round(abs_value *. 10.0)) /. 10.0
  let int_part = float.truncate(rounded)
  let frac =
    float.absolute_value(rounded -. int.to_float(int_part)) *. 10.0
    |> float.round
  let sign = case value <. 0.0 {
    True -> "-"
    False -> ""
  }
  sign <> int.to_string(int_part) <> "." <> int.to_string(frac)
}
