import deep_heating/config/home_config
import deep_heating/entity_id
import deep_heating/home_assistant/client as home_assistant
import deep_heating/home_assistant/ha_poller_actor
import deep_heating/log
import deep_heating/rooms/room_adjustments
import deep_heating/server
import deep_heating/state/state_aggregator_actor
import deep_heating/supervisor
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option
import gleam/set
import gleam/string

/// Default polling interval in milliseconds
const default_poll_interval_ms: Int = 10_000

/// Main entry point for Deep Heating.
/// Starts the supervision tree and HTTP/WebSocket server.
pub fn main() -> Nil {
  // Configure the logger first thing
  log.configure()
  log.info("Deep Heating starting...")

  // Build config from environment and start supervision tree
  case build_supervisor_config_with_rooms() {
    Error(reason) -> {
      log.error(
        "Failed to build config from environment: " <> string.inspect(reason),
      )
    }
    Ok(config) -> {
      case supervisor.start_with_home_config(config) {
        Error(e) -> {
          log.error("Failed to start supervision tree: " <> string.inspect(e))
        }
        Ok(started) -> {
          log.info("Supervision tree started")

          // Start polling - get the actual Subject (not via named lookup)
          let poller_subject = supervisor.get_ha_poller_subject(started.data)
          process.send(poller_subject, ha_poller_actor.StartPolling)
          log.debug("Started HA polling")

          // Get state aggregator subject
          let state_aggregator_subject =
            supervisor.get_state_aggregator_subject(started.data)
          log.debug("Got state aggregator reference")

          // Start the server
          start_server(state_aggregator_subject)
        }
      }
    }
  }

  // Keep the process alive
  process.sleep_forever()
}

/// Start the HTTP/WebSocket server
fn start_server(
  state_aggregator: process.Subject(state_aggregator_actor.Message),
) -> Nil {
  // Create room adjuster callback that forwards to StateAggregatorActor
  let room_adjuster = fn(room_name: String, adjustment: Float) {
    process.send(
      state_aggregator,
      state_aggregator_actor.AdjustRoom(room_name, adjustment),
    )
  }

  // Use PORT env var if set, otherwise default
  let port = server.port_from_env()
  let config =
    server.ServerConfig(
      port:,
      host: server.default_host,
      state_aggregator:,
      room_adjuster:,
    )

  // Start the HTTP/WebSocket server
  case server.start(config) {
    Ok(Nil) -> {
      log.info("Server started on http://localhost:" <> int.to_string(port))
    }
    Error(e) -> {
      log.error("Failed to start server: " <> e)
    }
  }
}

/// Error type for supervisor config building
pub type ConfigBuildError {
  HaClientError(home_assistant.HaError)
  HomeConfigError(home_config.ConfigError)
}

/// Build SupervisorConfigWithRooms from environment variables and home config file.
/// Returns Error if required env vars are not set or config cannot be loaded.
fn build_supervisor_config_with_rooms() -> Result(
  supervisor.SupervisorConfigWithRooms,
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

          Ok(supervisor.SupervisorConfigWithRooms(
            ha_client: ha_client,
            poller_config: poller_config,
            adjustments_path: adjustments_path,
            home_config: config,
            name_prefix: option.None,
            time_provider: option.None,
            house_mode_deps: supervisor.default_house_mode_deps(),
            room_actor_deps: supervisor.default_room_actor_deps(),
            ha_command_deps: supervisor.default_ha_command_deps(),
            state_aggregator_deps: supervisor.default_state_aggregator_deps(),
            ha_poller_deps: supervisor.default_ha_poller_deps(),
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
