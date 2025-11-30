import { Data } from 'effect';

/**
 * Domain errors for Home Assistant API interactions
 */

/**
 * Failed to connect to or communicate with Home Assistant
 * This includes network failures, authentication errors, and API errors
 */
export class HomeAssistantConnectionError extends Data.TaggedError(
  'HomeAssistantConnectionError',
)<{
  readonly message: string;
  readonly cause?: unknown;
}> {}

/**
 * Failed to set climate entity temperature
 * The entity exists but the temperature could not be set
 */
export class SetTemperatureError extends Data.TaggedError(
  'SetTemperatureError',
)<{
  readonly entityId: string;
  readonly targetTemperature: number;
  readonly cause?: unknown;
}> {}

/**
 * Failed to set climate entity HVAC mode
 * The entity exists but the mode could not be set
 */
export class SetHvacModeError extends Data.TaggedError('SetHvacModeError')<{
  readonly entityId: string;
  readonly mode: string;
  readonly cause?: unknown;
}> {}

/**
 * Union type for all Home Assistant errors
 */
export type HomeAssistantError =
  | HomeAssistantConnectionError
  | SetTemperatureError
  | SetHvacModeError;
