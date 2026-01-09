//// Test-safe logging infrastructure using Erlang's logger.
////
//// This module wraps the `logging` package to provide a simple API
//// for logging messages. Unlike `io.println`, Erlang's logger handles
//// process teardown gracefully, so background processes won't crash
//// when trying to log after test cleanup.
////
//// The log level can be configured via the LOG_LEVEL environment variable.
//// Supported values: debug, info, notice, warning, error, critical, alert, emergency
//// Default: info

import envoy
import gleam/string
import logging

/// Configure the logger. Call once at application startup.
/// Reads LOG_LEVEL from environment to set the log visibility level.
pub fn configure() -> Nil {
  logging.configure()
  case envoy.get("LOG_LEVEL") {
    Ok(level_str) ->
      case level_from_string(level_str) {
        Ok(level) -> logging.set_level(level)
        Error(_) -> Nil
      }
    Error(_) -> Nil
  }
}

/// Parse a string into a log level.
/// Case-insensitive. Returns Error(Nil) for invalid values.
pub fn level_from_string(s: String) -> Result(logging.LogLevel, Nil) {
  case string.lowercase(s) {
    "debug" -> Ok(logging.Debug)
    "info" -> Ok(logging.Info)
    "notice" -> Ok(logging.Notice)
    "warning" -> Ok(logging.Warning)
    "error" -> Ok(logging.Error)
    "critical" -> Ok(logging.Critical)
    "alert" -> Ok(logging.Alert)
    "emergency" -> Ok(logging.Emergency)
    _ -> Error(Nil)
  }
}

/// Log a debug message.
pub fn debug(message: String) -> Nil {
  logging.log(logging.Debug, message)
}

/// Log an info message.
pub fn info(message: String) -> Nil {
  logging.log(logging.Info, message)
}

/// Log a warning message.
pub fn warning(message: String) -> Nil {
  logging.log(logging.Warning, message)
}

/// Log an error message.
pub fn error(message: String) -> Nil {
  logging.log(logging.Error, message)
}

/// Format a message with actor context prefix.
/// Returns "[ActorName] message"
pub fn format_actor(actor_name: String, message: String) -> String {
  "[" <> actor_name <> "] " <> message
}

/// Format a message with entity ID prefix.
/// Returns "[entity_id] message"
pub fn format_entity(entity_id: String, message: String) -> String {
  "[" <> entity_id <> "] " <> message
}

/// Format a state change transition.
/// Returns "from→to"
pub fn state_change(from: String, to: String) -> String {
  from <> "→" <> to
}

// Actor-context logging convenience functions

/// Log a debug message with actor context.
pub fn actor_debug(actor_name: String, message: String) -> Nil {
  debug(format_actor(actor_name, message))
}

/// Log an info message with actor context.
pub fn actor_info(actor_name: String, message: String) -> Nil {
  info(format_actor(actor_name, message))
}

/// Log a warning message with actor context.
pub fn actor_warning(actor_name: String, message: String) -> Nil {
  warning(format_actor(actor_name, message))
}

/// Log an error message with actor context.
pub fn actor_error(actor_name: String, message: String) -> Nil {
  error(format_actor(actor_name, message))
}

// Entity-context logging convenience functions

/// Log a debug message with entity ID context.
pub fn entity_debug(entity_id: String, message: String) -> Nil {
  debug(format_entity(entity_id, message))
}

/// Log an info message with entity ID context.
pub fn entity_info(entity_id: String, message: String) -> Nil {
  info(format_entity(entity_id, message))
}

/// Log a warning message with entity ID context.
pub fn entity_warning(entity_id: String, message: String) -> Nil {
  warning(format_entity(entity_id, message))
}

/// Log an error message with entity ID context.
pub fn entity_error(entity_id: String, message: String) -> Nil {
  error(format_entity(entity_id, message))
}
