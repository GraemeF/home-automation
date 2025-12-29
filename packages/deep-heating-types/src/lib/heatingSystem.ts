import { Data, Effect } from 'effect';
import type { Observable } from 'rxjs';
import type { HeatingUpdate, TrvUpdate } from './deep-heating-types';
import type { ClimateEntityId } from './entities';
import type {
  GoodnightEventEntity,
  OperationalClimateMode,
  TemperatureSensorEntity,
} from './home-assistant';
import type { Temperature } from './temperature';

/**
 * Error type for HeatingSystem operations.
 * Uses Effect's Data.TaggedError pattern for typed error handling.
 */
export class HeatingSystemError extends Data.TaggedError('HeatingSystemError')<{
  readonly message: string;
  readonly cause?: unknown;
}> {}

/**
 * Abstract interface for heating system device communication.
 *
 * This interface expresses what the core heating logic needs from external
 * device communication, speaking purely in domain terms rather than external
 * system concepts (like Home Assistant entities).
 *
 * Implementations:
 * - HomeAssistantHeatingSystem: Wraps existing providers, translates HA entities
 * - InMemoryHeatingSystem: For testing, emits controllable fake domain data
 */
export interface HeatingSystem {
  /**
   * Stream of TRV state updates from the heating system.
   * Each update contains current temperature, target, mode, and heating status.
   */
  readonly trvUpdates: Observable<TrvUpdate>;

  /**
   * Stream of main heating system state updates.
   * Contains the central heating boiler/furnace state.
   */
  readonly heatingUpdates: Observable<HeatingUpdate>;

  /**
   * Stream of temperature sensor readings.
   * These are standalone sensors, not the built-in TRV sensors.
   */
  readonly temperatureReadings: Observable<TemperatureSensorEntity>;

  /**
   * Stream of sleep mode activation events.
   * Triggered when the household enters "goodnight" mode.
   */
  readonly sleepModeEvents: Observable<GoodnightEventEntity>;

  /**
   * Set the target temperature for a TRV.
   *
   * @param entityId - The climate entity ID of the TRV
   * @param temperature - The target temperature to set
   * @returns Effect that succeeds with void or fails with HeatingSystemError
   */
  setTrvTemperature(
    entityId: ClimateEntityId,
    temperature: Temperature,
  ): Effect.Effect<void, HeatingSystemError>;

  /**
   * Set the operating mode for a TRV.
   *
   * @param entityId - The climate entity ID of the TRV
   * @param mode - The operational mode (auto, heat, off)
   * @returns Effect that succeeds with void or fails with HeatingSystemError
   */
  setTrvMode(
    entityId: ClimateEntityId,
    mode: OperationalClimateMode,
  ): Effect.Effect<void, HeatingSystemError>;
}
