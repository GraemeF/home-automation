# Pop-Out E2E Acceptance Test Design

## Overview

GOOS-style (Growing Object-Oriented Software) outer acceptance test for the "Popping Out" feature. The test describes the complete user flow and will fail repeatedly as we build, with each failure guiding what to implement next.

## Design Decisions

### 1. Functional Page Object Pattern

Functions that take app state as argument rather than stateful objects:

```typescript
pipe(
  HeatingApp.make(page),
  Effect.flatMap(HeatingApp.initiatePopOut(returnTime)),
  Effect.flatMap(HeatingApp.expectAllRoomsAt(temperature)),
  // ...
);
```

### 2. Effect-Native

Full Effect types throughout. Each function returns `Effect<HeatingApp, TestError>` enabling typed error handling and composition.

### 3. Playwright Runner with Effect Internals

Playwright manages infrastructure (browser, servers, fixtures). Effect provides the functional abstraction for test steps:

```typescript
test('user can pop out and cancel', async ({ page }) => {
  await Effect.runPromise(
    pipe(
      HeatingApp.make(page),
      // Effect pipeline
    ).pipe(Effect.provide(TestConfigLayer(config))),
  );
});
```

### 4. ReturnTime Union Type

Supports both duration and specific time, matching feature requirements:

```typescript
type ReturnTime = { readonly _tag: 'duration'; readonly value: Duration.Duration } | { readonly _tag: 'specific'; readonly value: Date };
```

### 5. Ports and Adapters for Config

Test supplies config via Effect Layer (stub). Production uses file-reading adapter:

```typescript
const TestConfigLayer = (config: PopOutConfig): Layer.Layer<PopOutConfig> => Layer.succeed(PopOutConfig, config);
```

## File Structure

```
packages/deep-heating/e2e/
├── pop-out.spec.ts           # The acceptance test
├── smoke.spec.ts             # Existing smoke test
└── support/
    ├── heating-app.ts        # HeatingApp module (functional)
    └── return-time.ts        # ReturnTime type and constructors
```

## The Test

```typescript
test.describe('Popping Out', () => {
  const popOutTemperature = 10;

  test('user can pop out and cancel to return to normal schedule', async ({ page }) => {
    await Effect.runPromise(pipe(HeatingApp.make(page), Effect.flatMap(HeatingApp.initiatePopOut(ReturnTime.duration(Duration.hours(2)))), Effect.flatMap(HeatingApp.expectAllRoomsAt(popOutTemperature)), Effect.flatMap(HeatingApp.expectPopOutOverlay({ showsCancelOnly: true })), Effect.flatMap(HeatingApp.cancelPopOut), Effect.flatMap(HeatingApp.expectNormalSchedule)).pipe(Effect.provide(HeatingApp.TestConfigLayer({ popOutTemperature }))));
  });
});
```

## GOOS Approach

The test will fail immediately because:

- No "pop-out-button" exists yet
- No overlay component exists
- No backend state management exists

Each failure tells us what to implement next:

1. `getByTestId('pop-out-button')` fails → build UI button
2. `getByTestId('duration-selector')` fails → build time selection UI
3. Server doesn't respond → build WebSocket handler
4. Rooms don't update → build state management
5. etc.

Inner TDD loops (unit tests) drive each piece. When the outer test passes, the feature is complete.
