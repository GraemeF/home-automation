import * as Schema from '@effect/schema/Schema';
import { Temperature } from '@home-automation/deep-heating-types';
import { pipe } from 'effect/Function';
import { EntityId, HomeAssistantEntity } from '../entity';

export const SensorEntityId = pipe(
  EntityId,
  Schema.startsWith('sensor.'),
  Schema.brand('SensorEntityId')
);
export type SensorEntityId = Schema.Schema.To<typeof SensorEntityId>;

export const SensorEntity = pipe(
  HomeAssistantEntity,
  Schema.omit('state'),
  Schema.omit('attributes'),
  Schema.omit('entity_id'),
  Schema.extend(
    Schema.struct({
      entity_id: SensorEntityId,
      state: Schema.compose(Schema.NumberFromString, Temperature),
      attributes: Schema.struct({
        state_class: Schema.literal('measurement'),
        device_class: Schema.literal('temperature'),
        unit_of_measurement: Schema.literal('°C'),
        friendly_name: Schema.string,
      }),
    })
  )
);
export type SensorEntity = Schema.Schema.To<typeof SensorEntity>;
