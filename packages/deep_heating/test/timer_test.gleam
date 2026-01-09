import deep_heating/timer.{type TimerRequest}
import gleam/erlang/process
import gleeunit/should

// =============================================================================
// real_send_after Tests
// =============================================================================

pub fn real_send_after_delivers_message_after_delay_test() {
  // Given a subject and a message
  let subject = process.new_subject()
  let msg = "hello"

  // When we send_after with a short delay
  timer.real_send_after(subject, 50, msg)

  // Then the message should NOT arrive immediately
  let immediate_result = process.receive(subject, 10)
  immediate_result |> should.be_error

  // But it SHOULD arrive after the delay
  let delayed_result = process.receive(subject, 100)
  delayed_result |> should.be_ok
  let assert Ok(received) = delayed_result
  received |> should.equal("hello")
}

// =============================================================================
// spy_send_after Tests
// =============================================================================

pub fn spy_send_after_notifies_spy_of_timer_request_test() {
  // Given a spy subject to capture timer requests
  let spy: process.Subject(TimerRequest(String)) = process.new_subject()

  // And a send_after function using the spy
  let send_after = timer.spy_send_after(spy)

  // And a target subject for messages
  let target = process.new_subject()

  // When we call send_after
  send_after(target, 5000, "spy test")

  // Then the spy should receive the timer request details
  let assert Ok(request) = process.receive(spy, 100)
  request.delay_ms |> should.equal(5000)
  request.msg |> should.equal("spy test")
}

pub fn spy_send_after_does_not_deliver_to_target_test() {
  // Given a spy subject
  let spy: process.Subject(TimerRequest(String)) = process.new_subject()
  let send_after = timer.spy_send_after(spy)

  // And a target subject
  let target = process.new_subject()

  // When we call send_after via spy
  send_after(target, 100, "should not arrive")

  // Then the target should NOT receive the message
  // (spy_send_after only notifies the spy, doesn't actually send)
  let result = process.receive(target, 50)
  result |> should.be_error
}

pub fn spy_send_after_captures_multiple_requests_test() {
  // Given a spy subject
  let spy: process.Subject(TimerRequest(Int)) = process.new_subject()
  let send_after = timer.spy_send_after(spy)

  // And a target subject
  let target = process.new_subject()

  // When we make multiple timer requests
  send_after(target, 100, 1)
  send_after(target, 200, 2)
  send_after(target, 300, 3)

  // Then the spy should capture all requests in order
  let assert Ok(r1) = process.receive(spy, 100)
  let assert Ok(r2) = process.receive(spy, 100)
  let assert Ok(r3) = process.receive(spy, 100)

  r1.delay_ms |> should.equal(100)
  r1.msg |> should.equal(1)

  r2.delay_ms |> should.equal(200)
  r2.msg |> should.equal(2)

  r3.delay_ms |> should.equal(300)
  r3.msg |> should.equal(3)
}
