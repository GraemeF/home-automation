import gleam/io
import gleam/erlang/process

/// Main entry point for Deep Heating.
/// Will start the supervision tree once actors are implemented.
pub fn main() -> Nil {
  io.println("Deep Heating starting...")

  // TODO: Start supervision tree here
  // For now, just keep the process alive
  process.sleep_forever()
}
