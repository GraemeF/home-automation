import * as Schema from '@effect/schema/Schema';
import { pipe } from 'effect/Function';
import {
  ClimateEntityId,
  EntityId,
  EventEntityId,
  SensorEntityId,
} from '../entities';
import { Temperature } from '../temperature';

export const BaseEntity = Schema.struct({
  last_changed: pipe(Schema.string, Schema.dateFromString),
  last_updated: pipe(Schema.string, Schema.dateFromString),
  context: Schema.struct({
    id: Schema.string,
    parent_id: Schema.optional(Schema.nullable(Schema.string)),
    user_id: Schema.optional(Schema.nullable(Schema.string)),
  }),
});
export type BaseEntity = Schema.Schema.To<typeof BaseEntity>;

export const OtherEntity = pipe(
  BaseEntity,
  Schema.extend(
    Schema.struct({
      state: Schema.string,
      entity_id: EntityId,
      attributes: Schema.object,
    })
  )
);
export type OtherEntity = BaseEntity;

export const SensorEntity = pipe(
  BaseEntity,
  Schema.extend(
    Schema.struct({
      entity_id: SensorEntityId,
    })
  )
);
export type SensorEntity = Schema.Schema.To<typeof SensorEntity>;

export const TemperatureSensorEntity = pipe(
  SensorEntity,
  Schema.extend(
    Schema.struct({
      state: Schema.compose(Schema.NumberFromString, Temperature),
      attributes: Schema.struct({
        state_class: Schema.literal('measurement'),
        device_class: Schema.optional(Schema.literal('temperature')),
        unit_of_measurement: Schema.literal('°C'),
        friendly_name: Schema.string,
      }),
    })
  )
);
export type TemperatureSensorEntity = Schema.Schema.To<
  typeof TemperatureSensorEntity
>;

export const ClimateMode = Schema.literal('auto', 'heat', 'off');
export type ClimateMode = Schema.Schema.To<typeof ClimateMode>;

export const HassHvacAction = Schema.literal('idle', 'heating');
export type HassHvacAction = Schema.Schema.To<typeof HassHvacAction>;

export const ClimateEntity = pipe(
  BaseEntity,
  Schema.extend(
    Schema.struct({
      entity_id: ClimateEntityId,
      state: ClimateMode,
      attributes: Schema.struct({
        hvac_modes: Schema.array(Schema.string),
        min_temp: Temperature,
        max_temp: Temperature,
        preset_modes: Schema.optional(Schema.array(Schema.string)),
        current_temperature: Temperature,
        temperature: Temperature,
        hvac_action: Schema.optional(HassHvacAction),
        preset_mode: Schema.optional(Schema.string),
        friendly_name: Schema.string,
        supported_features: Schema.number,
      }),
    })
  )
);
export type ClimateEntity = Schema.Schema.To<typeof ClimateEntity>;

export const ButtonPressEventEntity = pipe(
  BaseEntity,
  Schema.extend(
    Schema.struct({
      entity_id: EventEntityId,
      state: pipe(Schema.string, Schema.dateFromString),
      attributes: Schema.struct({
        event_type: Schema.string,
        device_class: Schema.optional(Schema.literal('button')),
        friendly_name: Schema.string,
      }),
    })
  )
);
export type ButtonPressEventEntity = Schema.Schema.To<
  typeof ButtonPressEventEntity
>;

export const HomeAssistantEntity = Schema.union(
  TemperatureSensorEntity,
  ButtonPressEventEntity,
  ClimateEntity,
  OtherEntity
);
export type HomeAssistantEntity = Schema.Schema.To<typeof HomeAssistantEntity>;