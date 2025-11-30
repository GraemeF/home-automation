import { describe, expect, it } from 'bun:test';
import { Effect, pipe } from 'effect';
import {
  HomeAssistantConnectionError,
  SetHvacModeError,
  SetTemperatureError,
} from './errors';

describe('HomeAssistant errors', () => {
  describe('HomeAssistantConnectionError', () => {
    it('has the correct _tag', () => {
      const error = new HomeAssistantConnectionError({
        message: 'Connection failed',
      });
      expect(error._tag).toBe('HomeAssistantConnectionError');
    });

    it('can be caught with Effect.catchTag', () =>
      Effect.runPromise(
        pipe(
          new HomeAssistantConnectionError({
            message: 'Test error',
            cause: new Error('Network error'),
          }),
          Effect.fail,
          Effect.catchTag('HomeAssistantConnectionError', (error) =>
            Effect.succeed(error.message),
          ),
        ),
      ).then((result) => {
        expect(result).toBe('Test error');
      }));

    it('preserves the cause', () => {
      const cause = new Error('Network error');
      const error = new HomeAssistantConnectionError({
        message: 'Connection failed',
        cause,
      });
      expect(error.cause).toBe(cause);
    });
  });

  describe('SetTemperatureError', () => {
    it('has the correct _tag', () => {
      const error = new SetTemperatureError({
        entityId: 'climate.kitchen',
        targetTemperature: 21,
      });
      expect(error._tag).toBe('SetTemperatureError');
    });

    it('can be caught with Effect.catchTag', () =>
      Effect.runPromise(
        pipe(
          new SetTemperatureError({
            entityId: 'climate.kitchen',
            targetTemperature: 21,
          }),
          Effect.fail,
          Effect.catchTag('SetTemperatureError', (error) =>
            Effect.succeed({
              entityId: error.entityId,
              targetTemperature: error.targetTemperature,
            }),
          ),
        ),
      ).then((result) => {
        expect(result.entityId).toBe('climate.kitchen');
        expect(result.targetTemperature).toBe(21);
      }));
  });

  describe('SetHvacModeError', () => {
    it('has the correct _tag', () => {
      const error = new SetHvacModeError({
        entityId: 'climate.kitchen',
        mode: 'heat',
      });
      expect(error._tag).toBe('SetHvacModeError');
    });

    it('can be caught with Effect.catchTag', () =>
      Effect.runPromise(
        pipe(
          new SetHvacModeError({
            entityId: 'climate.kitchen',
            mode: 'heat',
          }),
          Effect.fail,
          Effect.catchTag('SetHvacModeError', (error) =>
            Effect.succeed({
              entityId: error.entityId,
              mode: error.mode,
            }),
          ),
        ),
      ).then((result) => {
        expect(result.entityId).toBe('climate.kitchen');
        expect(result.mode).toBe('heat');
      }));
  });
});
