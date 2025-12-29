import { Context, Effect, Layer, pipe } from 'effect';
import { describe, expect, test } from 'bun:test';
import { EMPTY } from 'rxjs';
import { HeatingSystem } from './heatingSystem';

describe('HeatingSystem', () => {
  test('can be used as an Effect Service via Context.Tag', async () => {
    // Create a mock implementation with proper type
    const mockHeatingSystem: Context.Tag.Service<typeof HeatingSystem> = {
      trvUpdates: EMPTY,
      heatingUpdates: EMPTY,
      temperatureReadings: EMPTY,
      sleepModeEvents: EMPTY,
      setTrvTemperature: () => Effect.void,
      setTrvMode: () => Effect.void,
    };

    // Create a test layer
    const TestLayer = Layer.succeed(HeatingSystem, mockHeatingSystem);

    // Use HeatingSystem as a service in Effect and verify it works
    const result = await pipe(
      HeatingSystem,
      Effect.map((system) => system.trvUpdates),
      Effect.provide(TestLayer),
      Effect.runPromise,
    );

    expect(result).toBe(EMPTY);
  });
});
