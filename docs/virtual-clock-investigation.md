# Virtual Clock Investigation (dh-33jq.74)

Investigation into whether a virtual clock pattern similar to Effect's `TestClock` is feasible in Gleam/OTP for deterministic timer testing.

## Context

The fix for dh-33jq.72 uses `spy_send_after` with manual message delivery for deterministic timer testing. This works for single-timer-at-a-time scenarios, but has a latent danger: tests could deliver timer messages in impossible orders when multiple timers are pending.

## Current Implementation

### How `spy_send_after` Works

```gleam
/// Test implementation - notifies spy when timer would be set.
/// Does NOT actually deliver the message to the target.
pub fn spy_send_after(spy: Subject(TimerRequest(msg))) -> SendAfter(msg) {
  fn(subject: Subject(msg), delay_ms: Int, msg: msg) -> TimerHandle {
    process.send(spy, TimerRequest(subject, delay_ms, msg))
    NoTimer
  }
}
```

**Current test pattern:**
1. Inject `spy_send_after` into actor
2. Capture timer requests via spy subject
3. Manually send the message to "fire" the timer: `process.send(actor, ReEvaluateMode)`
4. Verify timer reschedules by receiving next request from spy

**The problem:** With multiple pending timers, the test controls firing order. If Timer A (delay: 10ms) and Timer B (delay: 5ms) are both pending, tests could fire A before B - an impossible ordering in real execution.

## Effect's TestClock

Effect's `TestClock` works because Effect controls the entire execution runtime:

```typescript
// Effect TestClock usage
const test = Effect.gen(function* () {
  const fiber = yield* Effect.sleep("5 minutes").pipe(Effect.fork)

  // Advance virtual time - all timers scheduled at or before fire IN ORDER
  yield* TestClock.adjust("1 minute")

  const result = yield* Fiber.join(fiber)
})
```

Key insight: `TestClock.adjust(duration)` fires all pending timers **in correct chronological order** up to the new virtual time.

## Gleam Ecosystem Options

### gtempo Library

The `gtempo` library provides a `tempo/mock` module for mocking current system time:

```gleam
import tempo/mock

mock.freeze_time(datetime.literal("2024-06-21T13:42:11.314Z"))
mock.enable_sleep_warp()  // Sleep calls return instantly
```

**Limitation:** This mocks `DateTime` retrieval, NOT timer delivery. Timers scheduled via `erlang:send_after` still fire based on real time.

### Erlang/OTP Options

- **meck:** Can mock Erlang modules but struggles with BIFs like `erlang:send_after`
- **No built-in virtual time:** OTP provides no mechanism to intercept/control timer firing globally

## Virtual Clock Design for Gleam

Since we already inject `SendAfter` as a dependency, we CAN build a virtual clock that maintains correct timer ordering.

### Proposed API

```gleam
// Type for the virtual clock actor
pub opaque type VirtualClock

// Timer entry stored in the clock
pub type PendingTimer(msg) {
  PendingTimer(
    fire_time: Int,          // Absolute virtual time when timer should fire
    subject: Subject(msg),   // Target to receive the message
    msg: msg,                // Message to send
  )
}

/// Create a new virtual clock starting at time 0
pub fn start() -> Result(VirtualClock, StartError)

/// Create a new virtual clock starting at a specific time
pub fn start_at(initial_time_ms: Int) -> Result(VirtualClock, StartError)

/// Get a SendAfter function bound to this virtual clock.
/// Timer requests are queued with absolute fire times.
/// Messages are NOT delivered until advance() is called.
pub fn send_after(clock: VirtualClock) -> SendAfter(msg)

/// Get the current virtual time
pub fn current_time(clock: VirtualClock) -> Int

/// Advance virtual time by duration.
/// Fires all timers scheduled at or before new time, IN ORDER by fire_time.
/// Returns the number of timers fired.
pub fn advance(clock: VirtualClock, duration_ms: Int) -> Int

/// Advance virtual time to fire exactly the next pending timer.
/// Returns the timer that was fired, or None if no timers pending.
pub fn advance_to_next(clock: VirtualClock) -> Option(PendingTimer(msg))

/// Get count of pending timers (for test assertions)
pub fn pending_count(clock: VirtualClock) -> Int
```

### Implementation Sketch

```gleam
// Internal state
type State(msg) {
  State(
    current_time_ms: Int,
    pending_timers: List(PendingTimer(msg)),  // Sorted by fire_time
  )
}

// Message type for the virtual clock actor
type Message(msg) {
  ScheduleTimer(subject: Subject(msg), delay_ms: Int, msg: msg)
  Advance(duration_ms: Int, reply: Subject(Int))
  GetTime(reply: Subject(Int))
  GetPendingCount(reply: Subject(Int))
}

// When a timer is scheduled:
fn handle_schedule(state: State(msg), subject, delay_ms, msg) -> State(msg) {
  let fire_time = state.current_time_ms + delay_ms
  let timer = PendingTimer(fire_time, subject, msg)
  let new_pending = insert_sorted(state.pending_timers, timer)
  State(..state, pending_timers: new_pending)
}

// When time is advanced:
fn handle_advance(state: State(msg), duration_ms: Int) -> #(State(msg), Int) {
  let new_time = state.current_time_ms + duration_ms
  let #(to_fire, remaining) = partition_by_time(state.pending_timers, new_time)

  // Fire timers IN ORDER (list is already sorted by fire_time)
  list.each(to_fire, fn(timer) {
    process.send(timer.subject, timer.msg)
  })

  let new_state = State(current_time_ms: new_time, pending_timers: remaining)
  #(new_state, list.length(to_fire))
}
```

### Usage Example

```gleam
pub fn timer_reschedules_in_correct_order_test() {
  let assert Ok(clock) = virtual_clock.start()

  let actor = start_actor_with_options(
    send_after: virtual_clock.send_after(clock),
    // ...
  )

  // Actor schedules Timer A at 10ms and Timer B at 5ms during init
  virtual_clock.pending_count(clock) |> should.equal(2)

  // Advance by 6ms - only Timer B should fire (fire_time: 5ms)
  let fired = virtual_clock.advance(clock, 6)
  fired |> should.equal(1)

  // Advance by 5ms more - Timer A should fire (fire_time: 10ms)
  let fired2 = virtual_clock.advance(clock, 5)
  fired2 |> should.equal(1)
}
```

## Challenges

### 1. Type Safety with Multiple Message Types

The current `SendAfter(msg)` is parameterized by message type. A virtual clock actor needs to handle timers for different message types.

**Options:**
- Make `VirtualClock` generic over message type (one clock per actor type)
- Use type erasure with Dynamic (loses type safety)
- Create a clock factory pattern

**Recommendation:** One virtual clock per actor under test. This matches how tests currently work and maintains type safety.

### 2. Cross-Process Timer Delivery

When `advance()` fires timers, it sends messages to actor subjects. Since the virtual clock is a separate process, there's a brief window where:
1. Virtual clock sends message to actor
2. Actor processes message and schedules new timer
3. Virtual clock continues firing more timers

This could cause subtle ordering issues if an actor's timer callback schedules a new timer that should fire before other pending timers.

**Mitigation:** After each timer fire, yield to scheduler to allow target actors to process messages before continuing. This is imperfect but likely sufficient for most test scenarios.

### 3. Timer Cancellation

The current `TimerHandle` type supports cancellation. A virtual clock would need to support this:

```gleam
pub type VirtualTimerHandle {
  VirtualTimerHandle(clock: VirtualClock, timer_id: Int)
}

pub fn cancel_virtual_timer(handle: VirtualTimerHandle) -> Nil
```

This adds complexity but is necessary for graceful shutdown tests.

## Tradeoffs Analysis

| Aspect | Current (spy_send_after) | Virtual Clock |
|--------|--------------------------|---------------|
| **Complexity** | Simple - just capture and forward | Moderate - actor state, sorting, type gymnastics |
| **Type Safety** | Full | Full (with one clock per message type) |
| **Timer Ordering** | Manual (can be wrong) | Automatic (always correct) |
| **Multiple Timers** | Requires careful manual ordering | Handles automatically |
| **Cancellation** | Not needed (NoTimer) | Needs implementation |
| **Cross-Actor** | Each actor has own spy | Could share clock (complicates types) |
| **Learning Curve** | Minimal | Moderate |
| **Maintenance** | None | New module to maintain |

## Recommendation

**Feasibility: YES** - A virtual clock is definitely implementable in Gleam/OTP using the existing dependency injection pattern.

**Cost-Benefit Analysis:**

The virtual clock provides guarantees about timer ordering that the current spy approach cannot. However:

1. **Current codebase usage:** Most timer tests involve single timers (HouseModeActor, RoomActor, HaPollerActor all schedule one periodic timer at a time)

2. **Multiple timer scenarios:** None of the current actors schedule multiple concurrent timers

3. **Future risk:** If we add actors with multiple concurrent timers, the current approach becomes dangerous

**Verdict:** The virtual clock is **technically feasible but currently overkill** for this codebase. The spy_send_after pattern with manual firing is sufficient for single-timer actors.

### If We Decide to Implement

Start minimal:
1. Single message type per clock (type-safe)
2. Basic advance() and pending_count()
3. No cancellation initially (can add later)
4. One test to validate the pattern

Defer:
- Multi-message-type support
- Timer cancellation
- Cross-actor clock sharing

## Related Issues

- **dh-33jq.72:** Timer test fix that prompted this investigation
- **dh-33jq.73:** Another timer test that could benefit
- **dh-h4b2.8:** spy_and_instant_send_after variant (simpler alternative)

## Conclusion

A virtual clock for Gleam/OTP is **feasible** but **not currently necessary** for this codebase. The existing `spy_send_after` + manual firing pattern is sufficient for the single-timer-at-a-time scenarios we have.

If future development introduces actors with multiple concurrent timers, revisit this design and implement the virtual clock module.
