import * as Schema from '@effect/schema/Schema';
import { pipe } from 'effect';

export const EntityId = pipe(
  Schema.string,
  Schema.nonEmpty(),
  Schema.brand('EntityId')
);
export type EntityId = Schema.Schema.To<typeof EntityId>;

export const ClimateEntityId = pipe(
  EntityId,
  Schema.startsWith('climate.'),
  Schema.brand('ClimateEntityId')
);
export type ClimateEntityId = Schema.Schema.To<typeof ClimateEntityId>;

export const SensorEntityId = pipe(
  EntityId,
  Schema.startsWith('sensor.'),
  Schema.brand('SensorEntityId')
);
export type SensorEntityId = Schema.Schema.To<typeof SensorEntityId>;

export const EventEntityId = pipe(
  EntityId,
  Schema.startsWith('event.'),
  Schema.brand('EventEntityId')
);
export type EventEntityId = Schema.Schema.To<typeof EventEntityId>;

export const InputButtonEntityId = pipe(
  EntityId,
  Schema.startsWith('input_button.'),
  Schema.brand('InputButtonEntityId')
);
export type InputButtonEntityId = Schema.Schema.To<typeof InputButtonEntityId>;

export const GoodnightEntityId = Schema.union(
  EventEntityId,
  InputButtonEntityId
);
export type GoodnightEntityId = Schema.Schema.To<typeof GoodnightEntityId>;
