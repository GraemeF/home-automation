import deep_heating/state/state_aggregator_actor
import deep_heating/entity_id
import deep_heating/home_assistant/client as home_assistant
import deep_heating/home_assistant/ha_poller_actor
import deep_heating/config/home_config
import deep_heating/rooms/room_adjustments
import deep_heating/server
import deep_heating/supervisor
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/option
import gleam/set
import gleam/string

/// Default polling interval in milliseconds
const default_poll_interval_ms: Int = 10_000

/// Main entry point for Deep Heating.
/// Starts the supervision tree and HTTP/WebSocket server.
pub fn main() -> Nil {
  io.println("Deep Heating starting...")

  // Try to start with HA integration, fall back to dev mode
  let start_result = case build_supervisor_config() {
    Ok(config) -> {
      io.println("Starting with Home Assistant integration...")
      supervisor.start_with_config(config)
    }
    Error(reason) -> {
      io.println(
        "Starting in dev mode (no HA integration): " <> string.inspect(reason),
      )
      supervisor.start()
    }
  }

  // Continue with server startup
  case start_result {
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

          // Use PORT env var if set, otherwise default
          let port = server.port_from_env()
          let config =
            server.ServerConfig(
              port:,
              host: server.default_host,
              state_aggregator: aggregator_ref.subject,
              room_adjuster:,
            )

          // Start the HTTP/WebSocket server
          case server.start(config) {
            Ok(Nil) -> {
              io.println(
                "Server started on http://localhost:" <> int.to_string(port),
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

/// Error type for supervisor config building
pub type ConfigBuildError {
  HaClientError(home_assistant.HaError)
  HomeConfigError(home_config.ConfigError)
}

/// Build SupervisorConfig from environment variables and home config file.
/// Returns Error if SUPERVISOR_URL or SUPERVISOR_TOKEN are not set,
/// or if HOME_CONFIG_PATH is not set or the config file cannot be loaded.
fn build_supervisor_config() -> Result(
  supervisor.SupervisorConfig,
  ConfigBuildError,
) {
  // Try to get HaClient from env vars
  case home_assistant.ha_client_from_env() {
    Error(e) -> Error(HaClientError(e))
    Ok(ha_client) -> {
      // Try to load home config
      case home_config.load_from_env() {
        Error(e) -> Error(HomeConfigError(e))
        Ok(config) -> {
          // Build PollerConfig from home config
          let poller_config = build_poller_config(config)

          // Get adjustments path from env, or use default
          let adjustments_path = room_adjustments.path_from_env_with_default()

          Ok(supervisor.SupervisorConfig(
            ha_client: ha_client,
            poller_config: poller_config,
            adjustments_path: adjustments_path,
          ))
        }
      }
    }
  }
}

/// Build PollerConfig from HomeConfig
fn build_poller_config(
  config: home_config.HomeConfig,
) -> ha_poller_actor.PollerConfig {
  // Extract managed TRV IDs (TRVs that have schedules)
  let managed_trv_ids =
    config.rooms
    |> list.filter(fn(room) { option.is_some(room.schedule) })
    |> list.flat_map(fn(room) { room.climate_entity_ids })
    |> set.from_list

  // Extract managed sensor IDs (rooms with temperature sensors)
  let managed_sensor_ids =
    config.rooms
    |> list.filter(fn(room) { option.is_some(room.schedule) })
    |> list.filter_map(fn(room) {
      option.to_result(room.temperature_sensor_entity_id, Nil)
    })
    |> set.from_list

  ha_poller_actor.PollerConfig(
    poll_interval_ms: default_poll_interval_ms,
    heating_entity_id: config.heating_id,
    sleep_button_entity_id: entity_id.goodnight_entity_id_to_string(
      config.sleep_switch_id,
    ),
    managed_trv_ids: managed_trv_ids,
    managed_sensor_ids: managed_sensor_ids,
  )
}
