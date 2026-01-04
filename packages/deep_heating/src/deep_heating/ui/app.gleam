import deep_heating/ui/model
import deep_heating/ui/update.{type Dependencies}
import deep_heating/ui/view
import lustre

/// Create the Lustre application with the given dependencies.
/// Dependencies allow injecting actor communication for real usage.
pub fn app(deps: Dependencies) {
  lustre.application(model.init, update.make_update(deps), view.view)
}

/// Create a simple Lustre application with no-op dependencies.
/// Useful for testing or UI development without a backend.
pub fn simple_app() {
  lustre.application(model.init, update.update, view.view)
}
