import deep_heating/ui/model
import deep_heating/ui/view
import lustre/element

pub fn view_renders_without_error_test() {
  let m = model.init(Nil)
  let _html = view.view(m) |> element.to_string()
  // Just verify it doesn't crash
  Nil
}
