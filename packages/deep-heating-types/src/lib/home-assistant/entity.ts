import * as Schema from '@effect/schema/Schema';
import { pipe } from 'effect/Function';
import {
  ClimateEntityId,
  EntityId,
  EventEntityId,
  InputButtonEntityId,
  SensorEntityId,
} from '../entities';
import { Temperature } from '../temperature';

export const BaseEntity = Schema.struct({
  last_changed: Schema.Date,
  last_updated: Schema.Date,
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
    }),
  ),
);
export type OtherEntity = BaseEntity;

export const SensorEntity = pipe(
  BaseEntity,
  Schema.extend(
    Schema.struct({
      entity_id: SensorEntityId,
    }),
  ),
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
    }),
  ),
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
    }),
  ),
);
export type ClimateEntity = Schema.Schema.To<typeof ClimateEntity>;

export const ButtonPressEventEntity = pipe(
  BaseEntity,
  Schema.extend(
    Schema.struct({
      entity_id: EventEntityId,
      state: Schema.DateFromString,
      attributes: Schema.struct({
        friendly_name: Schema.string,
      }),
    }),
  ),
);
export type ButtonPressEventEntity = Schema.Schema.To<
  typeof ButtonPressEventEntity
>;

export const InputButtonEntity = pipe(
  BaseEntity,
  Schema.extend(
    Schema.struct({
      entity_id: InputButtonEntityId,
      state: Schema.Date,
      attributes: Schema.struct({
        friendly_name: Schema.string,
      }),
    }),
  ),
);
export type InputButtonEntity = Schema.Schema.To<typeof InputButtonEntity>;

export const GoodnightEventEntity = Schema.union(
  InputButtonEntity,
  ButtonPressEventEntity,
);
export type GoodnightEventEntity = Schema.Schema.To<
  typeof GoodnightEventEntity
>;

export const HomeAssistantEntity = Schema.union(
  TemperatureSensorEntity,
  GoodnightEventEntity,
  ClimateEntity,
  OtherEntity,
);
export type HomeAssistantEntity = Schema.Schema.To<typeof HomeAssistantEntity>;

export const isSchema =
  <From, To>(schema: Schema.Schema<never, From, To>) =>
  (e: unknown): e is To =>
    Schema.is(schema)(e);
