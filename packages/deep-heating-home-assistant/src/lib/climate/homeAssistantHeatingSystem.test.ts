import { Effect, Layer, pipe } from 'effect';
import { describe, expect, test } from 'bun:test';
import { Home, HeatingSystem } from '@home-automation/deep-heating-types';
import { HomeAssistantHeatingSystemLive } from './homeAssistantHeatingSystem';
import { HomeAssistantApiTest } from '../home-assistant-api';

describe('HomeAssistantHeatingSystemLive', () => {
  const testHome: Home = {
    heatingId: 'climate.main',
    sleepSwitchId: 'input_button.goodnight',
    rooms: [],
  };

  test('provides HeatingSystem service when given Home config', async () => {
    // Arrange: Create test layer with mocked HA API
    const TestApiLayer = HomeAssistantApiTest(Effect.succeed([]));
    const HeatingSystemLayer = HomeAssistantHeatingSystemLive(testHome).pipe(
      Layer.provide(TestApiLayer),
    );

    // Act: Access HeatingSystem from the layer
    const result = await pipe(
      HeatingSystem,
      Effect.map((system) => typeof system.trvUpdates),
      Effect.provide(HeatingSystemLayer),
      Effect.runPromise,
    );

    // Assert: HeatingSystem provides trvUpdates observable
    expect(result).toBe('object');
  });
});
