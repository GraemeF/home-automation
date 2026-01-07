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
