//// Test-safe logging infrastructure using Erlang's logger.
////
//// This module wraps the `logging` package to provide a simple API
//// for logging messages. Unlike `io.println`, Erlang's logger handles
//// process teardown gracefully, so background processes won't crash
//// when trying to log after test cleanup.

import logging

/// Configure the logger. Call once at application startup.
pub fn configure() -> Nil {
  logging.configure()
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
