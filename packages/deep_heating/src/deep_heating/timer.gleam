//// Timer utilities for injectable send_after functionality.
////
//// This module provides three implementations of send_after:
//// - `real_send_after`: Production implementation using process.send_after
//// - `instant_send_after`: Test implementation that sends immediately
//// - `spy_send_after`: Test implementation that notifies a spy subject

import gleam/erlang/process.{type Subject}

/// Injectable timer function type.
/// Takes a subject, delay in milliseconds, and the message to send.
pub type SendAfter(msg) =
  fn(Subject(msg), Int, msg) -> Nil

/// Request captured by spy_send_after.
/// Contains all the information about a timer request.
pub type TimerRequest(msg) {
  TimerRequest(subject: Subject(msg), delay_ms: Int, msg: msg)
}

/// Production implementation - uses real process.send_after.
/// The message will be delivered to the subject after delay_ms milliseconds.
pub fn real_send_after(subject: Subject(msg), delay_ms: Int, msg: msg) -> Nil {
  let _ = process.send_after(subject, delay_ms, msg)
  Nil
}

/// Test implementation - sends message immediately (no delay).
/// Useful for fast tests where you don't want to wait for timers.
pub fn instant_send_after(
  subject: Subject(msg),
  _delay_ms: Int,
  msg: msg,
) -> Nil {
  process.send(subject, msg)
}

/// Test implementation - notifies spy subject when timer would be set.
/// Does NOT actually deliver the message to the target.
/// Useful for verifying timer behavior without waiting.
pub fn spy_send_after(spy: Subject(TimerRequest(msg))) -> SendAfter(msg) {
  fn(subject: Subject(msg), delay_ms: Int, msg: msg) -> Nil {
    process.send(
      spy,
      TimerRequest(subject: subject, delay_ms: delay_ms, msg: msg),
    )
  }
}
