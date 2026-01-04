import lustre/attribute.{attribute}
import lustre/element.{type Element}
import lustre/element/svg

/// Icon size type for type-safe sizing.
pub type IconSize {
  IconSmall
  IconMedium
  IconLarge
}

fn size_to_px(size: IconSize) -> String {
  case size {
    IconSmall -> "16"
    IconMedium -> "24"
    IconLarge -> "32"
  }
}

/// Fire icon - displayed when heating is active.
pub fn fire(size: IconSize) -> Element(msg) {
  let px = size_to_px(size)
  svg.svg(
    [
      attribute("viewBox", "0 0 24 24"),
      attribute("width", px),
      attribute("height", px),
      attribute("fill", "currentColor"),
      attribute("data-testid", "fire-icon"),
    ],
    [
      svg.path([
        attribute(
          "d",
          "M17.66 11.2C17.43 10.9 17.15 10.64 16.89 10.38C16.22 9.78 15.46 9.35 14.82 8.72C13.33 7.26 13 4.85 13.95 3C13 3.23 12.17 3.75 11.46 4.32C8.87 6.4 7.85 10.07 9.07 13.22C9.11 13.32 9.15 13.42 9.15 13.55C9.15 13.77 9 13.97 8.8 14.05C8.57 14.15 8.33 14.09 8.14 13.93C8.08 13.88 8.04 13.83 8 13.76C6.87 12.33 6.69 10.28 7.45 8.64C5.78 10 4.87 12.3 5 14.47C5.06 14.97 5.12 15.47 5.29 15.97C5.43 16.57 5.7 17.17 6 17.7C7.08 19.43 8.95 20.67 10.96 20.92C13.1 21.19 15.39 20.8 17.03 19.32C18.86 17.66 19.5 15 18.56 12.72L18.43 12.46C18.22 12 17.66 11.2 17.66 11.2ZM14.5 17.5C14.22 17.74 13.76 18 13.4 18.1C12.28 18.5 11.16 17.94 10.5 17.28C11.69 17 12.4 16.12 12.61 15.23C12.78 14.43 12.46 13.77 12.33 13C12.21 12.26 12.23 11.63 12.5 10.94C12.69 11.32 12.89 11.7 13.13 12C13.9 13 15.11 13.44 15.37 14.8C15.41 14.94 15.43 15.08 15.43 15.23C15.46 16.05 15.1 16.95 14.5 17.5Z",
        ),
      ]),
    ],
  )
}

/// Plus circle icon (solid).
pub fn plus_circle_solid(size: IconSize) -> Element(msg) {
  let px = size_to_px(size)
  svg.svg(
    [
      attribute("viewBox", "0 0 24 24"),
      attribute("width", px),
      attribute("height", px),
      attribute("fill", "currentColor"),
      attribute("data-testid", "plus-circle-solid"),
    ],
    [
      svg.path([
        attribute("fill-rule", "evenodd"),
        attribute("clip-rule", "evenodd"),
        attribute(
          "d",
          "M12 2.25c-5.385 0-9.75 4.365-9.75 9.75s4.365 9.75 9.75 9.75 9.75-4.365 9.75-9.75S17.385 2.25 12 2.25ZM12.75 9a.75.75 0 0 0-1.5 0v2.25H9a.75.75 0 0 0 0 1.5h2.25V15a.75.75 0 0 0 1.5 0v-2.25H15a.75.75 0 0 0 0-1.5h-2.25V9Z",
        ),
      ]),
    ],
  )
}

/// Plus circle icon (outline).
pub fn plus_circle_outline(size: IconSize) -> Element(msg) {
  let px = size_to_px(size)
  svg.svg(
    [
      attribute("viewBox", "0 0 24 24"),
      attribute("width", px),
      attribute("height", px),
      attribute("fill", "none"),
      attribute("stroke", "currentColor"),
      attribute("stroke-width", "1.5"),
      attribute("data-testid", "plus-circle-outline"),
    ],
    [
      svg.path([
        attribute("stroke-linecap", "round"),
        attribute("stroke-linejoin", "round"),
        attribute("d", "M12 9v6m3-3H9m12 0a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z"),
      ]),
    ],
  )
}

/// Minus circle icon (solid).
pub fn minus_circle_solid(size: IconSize) -> Element(msg) {
  let px = size_to_px(size)
  svg.svg(
    [
      attribute("viewBox", "0 0 24 24"),
      attribute("width", px),
      attribute("height", px),
      attribute("fill", "currentColor"),
      attribute("data-testid", "minus-circle-solid"),
    ],
    [
      svg.path([
        attribute("fill-rule", "evenodd"),
        attribute("clip-rule", "evenodd"),
        attribute(
          "d",
          "M12 2.25c-5.385 0-9.75 4.365-9.75 9.75s4.365 9.75 9.75 9.75 9.75-4.365 9.75-9.75S17.385 2.25 12 2.25Zm-3 9.75a.75.75 0 0 1 0-1.5h6a.75.75 0 0 1 0 1.5H9Z",
        ),
      ]),
    ],
  )
}

/// Minus circle icon (outline).
pub fn minus_circle_outline(size: IconSize) -> Element(msg) {
  let px = size_to_px(size)
  svg.svg(
    [
      attribute("viewBox", "0 0 24 24"),
      attribute("width", px),
      attribute("height", px),
      attribute("fill", "none"),
      attribute("stroke", "currentColor"),
      attribute("stroke-width", "1.5"),
      attribute("data-testid", "minus-circle-outline"),
    ],
    [
      svg.path([
        attribute("stroke-linecap", "round"),
        attribute("stroke-linejoin", "round"),
        attribute("d", "M15 12H9m12 0a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z"),
      ]),
    ],
  )
}

/// Helper: choose plus icon based on adjustment state.
pub fn plus_icon(has_positive_adjustment: Bool, size: IconSize) -> Element(msg) {
  case has_positive_adjustment {
    True -> plus_circle_solid(size)
    False -> plus_circle_outline(size)
  }
}

/// Helper: choose minus icon based on adjustment state.
pub fn minus_icon(has_negative_adjustment: Bool, size: IconSize) -> Element(msg) {
  case has_negative_adjustment {
    True -> minus_circle_solid(size)
    False -> minus_circle_outline(size)
  }
}
