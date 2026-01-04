//// Main view composition for the Deep Heating dashboard.
////
//// Composes all UI components into the complete application view,
//// handling connection state, loading state, and room display.

import deep_heating/state.{type DeepHeatingState, type RoomState}
import deep_heating/ui/components/connection_overlay
import deep_heating/ui/components/heating_badge
import deep_heating/ui/components/room_card
import deep_heating/ui/model.{type Model}
import deep_heating/ui/msg.{type Msg}
import deep_heating/ui/room_sort
import gleam/list
import gleam/option.{None, Some}
import lustre/attribute.{attribute, class, href}
import lustre/element.{type Element, text}
import lustre/element/html.{a, div, li, span, ul}

/// Render the main application view from the model.
pub fn view(model: Model) -> Element(Msg) {
  div([attribute("data-testid", "app-root")], [
    connection_overlay.view(model.connected),
    main_content(model),
  ])
}

fn main_content(model: Model) -> Element(Msg) {
  div([attribute("data-testid", "main-content")], [
    breadcrumbs(),
    case model.state {
      None -> loading_placeholder()
      Some(state) -> home_view(state)
    },
  ])
}

fn breadcrumbs() -> Element(Msg) {
  ul([class("breadcrumbs text-sm mx-3.5 mt-2")], [
    li([], [a([href("/")], [text("Deep Heating")])]),
  ])
}

fn loading_placeholder() -> Element(Msg) {
  div(
    [
      class("flex items-center justify-center h-64"),
      attribute("data-testid", "loading-placeholder"),
    ],
    [span([class("loading loading-spinner loading-lg")], [])],
  )
}

fn home_view(state: DeepHeatingState) -> Element(Msg) {
  div([class("mx-3.5"), attribute("data-testid", "home-view")], [
    header_section(state),
    rooms_grid(state.rooms),
  ])
}

fn header_section(state: DeepHeatingState) -> Element(Msg) {
  div([class("flex flex-row justify-between items-center mb-2")], [
    heating_badge.view(state.is_heating),
  ])
}

fn rooms_grid(rooms: List(RoomState)) -> Element(Msg) {
  let sorted_rooms = room_sort.sort_by_temperature(rooms)

  div(
    [
      class("flex flex-row flex-wrap gap-2"),
      attribute("data-testid", "rooms-grid"),
    ],
    list.map(sorted_rooms, room_card.view),
  )
}
