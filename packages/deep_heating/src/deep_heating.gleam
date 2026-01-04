import deep_heating/actor/state_aggregator_actor
import deep_heating/server
import deep_heating/supervisor
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/string

/// Main entry point for Deep Heating.
/// Starts the supervision tree and HTTP/WebSocket server.
pub fn main() -> Nil {
  io.println("Deep Heating starting...")

  // Start the supervision tree
  case supervisor.start() {
    Ok(started) -> {
      io.println("Supervision tree started")

      // Get the state aggregator actor
      case supervisor.get_state_aggregator(started.data) {
        Ok(aggregator_ref) -> {
          io.println("Got state aggregator reference")

          // Create room adjuster callback that forwards to StateAggregatorActor
          let room_adjuster = fn(room_name: String, adjustment: Float) {
            process.send(
              aggregator_ref.subject,
              state_aggregator_actor.AdjustRoom(room_name, adjustment),
            )
          }

          let config =
            server.default_config(aggregator_ref.subject, room_adjuster)

          // Start the HTTP/WebSocket server
          case server.start(config) {
            Ok(Nil) -> {
              io.println(
                "Server started on http://localhost:"
                <> int.to_string(server.default_port),
              )
            }
            Error(e) -> {
              io.println("Failed to start server: " <> e)
            }
          }
        }
        Error(Nil) -> {
          io.println("Failed to get state aggregator reference")
        }
      }
    }
    Error(e) -> {
      io.println("Failed to start supervision tree: " <> string.inspect(e))
    }
  }

  // Keep the process alive
  process.sleep_forever()
}
