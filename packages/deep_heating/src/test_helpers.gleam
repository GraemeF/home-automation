//// Test helper utilities for silencing noisy OTP logs during tests.
////
//// Use `silence_otp_logs()` at the start of test setup to suppress
//// CRASH REPORT and SUPERVISOR REPORT messages, then call `restore_otp_logs()`
//// with the returned level to restore normal logging.

/// Opaque type representing a log level
pub type LogLevel

/// Silence all OTP/SASL logs (CRASH REPORT, SUPERVISOR REPORT, etc.)
/// Returns the previous log level so it can be restored later.
@external(erlang, "test_helpers_ffi", "silence_otp_logs")
pub fn silence_otp_logs() -> LogLevel

/// Restore the previous log level after silencing
@external(erlang, "test_helpers_ffi", "restore_otp_logs")
pub fn restore_otp_logs(level: LogLevel) -> Nil

/// Execute a function with all io output silenced.
/// Useful for tests that trigger expected error messages.
@external(erlang, "test_helpers_ffi", "with_silenced_io")
pub fn with_silenced_io(f: fn() -> a) -> a
