import birdie
import deep_heating/ui/icons.{IconLarge, IconMedium, IconSmall}
import gleam/string
import lustre/element

// =============================================================================
// Snapshot Tests - Verify icon rendering
// =============================================================================

pub fn fire_icon_small_test() {
  icons.fire(IconSmall)
  |> element.to_string()
  |> birdie.snap("fire_icon_small")
}

pub fn fire_icon_medium_test() {
  icons.fire(IconMedium)
  |> element.to_string()
  |> birdie.snap("fire_icon_medium")
}

pub fn fire_icon_large_test() {
  icons.fire(IconLarge)
  |> element.to_string()
  |> birdie.snap("fire_icon_large")
}

pub fn plus_circle_solid_test() {
  icons.plus_circle_solid(IconMedium)
  |> element.to_string()
  |> birdie.snap("plus_circle_solid")
}

pub fn plus_circle_outline_test() {
  icons.plus_circle_outline(IconMedium)
  |> element.to_string()
  |> birdie.snap("plus_circle_outline")
}

pub fn minus_circle_solid_test() {
  icons.minus_circle_solid(IconMedium)
  |> element.to_string()
  |> birdie.snap("minus_circle_solid")
}

pub fn minus_circle_outline_test() {
  icons.minus_circle_outline(IconMedium)
  |> element.to_string()
  |> birdie.snap("minus_circle_outline")
}

// =============================================================================
// Structure Tests - Verify SVG attributes
// =============================================================================

pub fn fire_icon_is_svg_test() {
  let html = icons.fire(IconMedium) |> element.to_string()
  let assert True = string.contains(html, "<svg")
}

pub fn fire_icon_has_test_id_test() {
  let html = icons.fire(IconMedium) |> element.to_string()
  let assert True = string.contains(html, "data-testid=\"fire-icon\"")
}

pub fn fire_icon_uses_current_color_test() {
  let html = icons.fire(IconMedium) |> element.to_string()
  let assert True = string.contains(html, "fill=\"currentColor\"")
}

pub fn plus_circle_solid_has_test_id_test() {
  let html = icons.plus_circle_solid(IconMedium) |> element.to_string()
  let assert True = string.contains(html, "data-testid=\"plus-circle-solid\"")
}

pub fn minus_circle_solid_has_test_id_test() {
  let html = icons.minus_circle_solid(IconMedium) |> element.to_string()
  let assert True = string.contains(html, "data-testid=\"minus-circle-solid\"")
}

pub fn icon_size_small_is_16px_test() {
  let html = icons.fire(IconSmall) |> element.to_string()
  let assert True = string.contains(html, "width=\"16\"")
  let assert True = string.contains(html, "height=\"16\"")
}

pub fn icon_size_medium_is_24px_test() {
  let html = icons.fire(IconMedium) |> element.to_string()
  let assert True = string.contains(html, "width=\"24\"")
  let assert True = string.contains(html, "height=\"24\"")
}

pub fn icon_size_large_is_32px_test() {
  let html = icons.fire(IconLarge) |> element.to_string()
  let assert True = string.contains(html, "width=\"32\"")
  let assert True = string.contains(html, "height=\"32\"")
}

// =============================================================================
// Helper Function Tests - Verify icon selection logic
// =============================================================================

pub fn plus_icon_solid_when_positive_adjustment_test() {
  let solid = icons.plus_circle_solid(IconMedium) |> element.to_string()
  let selected = icons.plus_icon(True, IconMedium) |> element.to_string()
  let assert True = solid == selected
}

pub fn plus_icon_outline_when_no_adjustment_test() {
  let outline = icons.plus_circle_outline(IconMedium) |> element.to_string()
  let selected = icons.plus_icon(False, IconMedium) |> element.to_string()
  let assert True = outline == selected
}

pub fn minus_icon_solid_when_negative_adjustment_test() {
  let solid = icons.minus_circle_solid(IconMedium) |> element.to_string()
  let selected = icons.minus_icon(True, IconMedium) |> element.to_string()
  let assert True = solid == selected
}

pub fn minus_icon_outline_when_no_adjustment_test() {
  let outline = icons.minus_circle_outline(IconMedium) |> element.to_string()
  let selected = icons.minus_icon(False, IconMedium) |> element.to_string()
  let assert True = outline == selected
}
