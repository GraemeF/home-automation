//// Timer utilities for injectable send_after functionality.
////
//// This module provides two implementations of send_after:
//// - `real_send_after`: Production implementation using process.send_after
//// - `spy_send_after`: Test implementation that notifies a spy subject
////
//// TimerHandle allows cancellation of pending timers for graceful shutdown.

import gleam/erlang/process.{type Subject, type Timer}

/// Handle to a timer that can be cancelled.
/// RealTimer wraps an actual Erlang timer reference.
/// NoTimer is used by test implementations that don't create real timers.
pub type TimerHandle {
  RealTimer(Timer)
  NoTimer
}

/// Injectable timer function type.
/// Takes a subject, delay in milliseconds, and the message to send.
/// Returns a TimerHandle that can be used to cancel the timer.
pub type SendAfter(msg) =
  fn(Subject(msg), Int, msg) -> TimerHandle

/// Request captured by spy_send_after.
/// Contains all the information about a timer request.
pub type TimerRequest(msg) {
  TimerRequest(subject: Subject(msg), delay_ms: Int, msg: msg)
}

/// Cancel a timer handle if it's a real timer.
/// Safe to call on NoTimer (does nothing).
/// Safe to call on already-fired timers (returns immediately).
pub fn cancel_handle(handle: TimerHandle) -> Nil {
  case handle {
    RealTimer(timer) -> {
      let _ = process.cancel_timer(timer)
      Nil
    }
    NoTimer -> Nil
  }
}

/// Production implementation - uses real process.send_after.
/// The message will be delivered to the subject after delay_ms milliseconds.
/// Returns a RealTimer handle that can be cancelled.
pub fn real_send_after(
  subject: Subject(msg),
  delay_ms: Int,
  msg: msg,
) -> TimerHandle {
  let timer = process.send_after(subject, delay_ms, msg)
  RealTimer(timer)
}

/// Test implementation - notifies spy subject when timer would be set.
/// Does NOT actually deliver the message to the target.
/// Useful for verifying timer behavior without waiting.
/// Returns NoTimer since no timer is actually created.
pub fn spy_send_after(spy: Subject(TimerRequest(msg))) -> SendAfter(msg) {
  fn(subject: Subject(msg), delay_ms: Int, msg: msg) -> TimerHandle {
    process.send(
      spy,
      TimerRequest(subject: subject, delay_ms: delay_ms, msg: msg),
    )
    NoTimer
  }
}
