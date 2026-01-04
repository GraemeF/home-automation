import deep_heating/ui/model
import deep_heating/ui/update
import deep_heating/ui/view
import lustre

/// Create the Lustre application.
pub fn app() {
  lustre.simple(model.init, update.update, view.view)
}
