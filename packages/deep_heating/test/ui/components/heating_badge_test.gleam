import birdie
import deep_heating/ui/components/heating_badge
import gleam/option.{None, Some}
import lustre/element

pub fn heating_badge_when_heating_test() {
  heating_badge.view(Some(True))
  |> element.to_string()
  |> birdie.snap("heating_badge_when_heating")
}

pub fn heating_badge_when_idle_test() {
  heating_badge.view(Some(False))
  |> element.to_string()
  |> birdie.snap("heating_badge_when_idle")
}

pub fn heating_badge_when_unknown_test() {
  heating_badge.view(None)
  |> element.to_string()
  |> birdie.snap("heating_badge_when_unknown")
}
