import deep_heating/ui/msg.{type Msg}
import gleam/option.{type Option, None, Some}
import lustre/attribute.{class}
import lustre/element.{type Element, text}
import lustre/element/html.{div, span}

/// Heating status badge showing whether the house is currently heating.
pub fn view(is_heating: Option(Bool)) -> Element(Msg) {
  let status_text = case is_heating {
    Some(True) -> "Heating"
    Some(False) -> "Idle"
    None -> "Unknown"
  }

  let badge_class = case is_heating {
    Some(True) -> "badge badge-error"
    Some(False) -> "badge badge-success"
    None -> "badge badge-ghost"
  }

  div([class("flex items-center gap-2")], [
    span([class(badge_class)], [text(status_text)]),
  ])
}
