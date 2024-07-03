import { Schema } from '@effect/schema';
import { pipe } from 'effect';

export const EntityId = pipe(
  Schema.String,
  Schema.nonEmpty(),
  Schema.brand('EntityId'),
);
export type EntityId = typeof EntityId.Type;

export const ClimateEntityId = pipe(
  EntityId,
  Schema.startsWith('climate.'),
  Schema.brand('ClimateEntityId'),
);
export type ClimateEntityId = typeof ClimateEntityId.Type;

export const SensorEntityId = pipe(
  EntityId,
  Schema.startsWith('sensor.'),
  Schema.brand('SensorEntityId'),
);
export type SensorEntityId = typeof SensorEntityId.Type;

export const EventEntityId = pipe(
  EntityId,
  Schema.startsWith('event.'),
  Schema.brand('EventEntityId'),
);
export type EventEntityId = typeof EventEntityId.Type;

export const InputButtonEntityId = pipe(
  EntityId,
  Schema.startsWith('input_button.'),
  Schema.brand('InputButtonEntityId'),
);
export type InputButtonEntityId = typeof InputButtonEntityId.Type;

export const GoodnightEntityId = Schema.Union(
  EventEntityId,
  InputButtonEntityId,
);
export type GoodnightEntityId = typeof GoodnightEntityId.Type;
