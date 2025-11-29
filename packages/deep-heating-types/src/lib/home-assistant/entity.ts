import { Schema } from 'effect';
import { pipe } from 'effect/Function';
import {
  ClimateEntityId,
  EntityId,
  EventEntityId,
  InputButtonEntityId,
  SensorEntityId,
} from '../entities';
import { Temperature } from '../temperature';

export const BaseEntity = Schema.Struct({
  last_changed: Schema.Date,
  last_updated: Schema.Date,
  context: Schema.Struct({
    id: Schema.String,
    parent_id: Schema.UndefinedOr(Schema.NullOr(Schema.String)),
    user_id: Schema.UndefinedOr(Schema.NullOr(Schema.String)),
  }),
});
export type BaseEntity = typeof BaseEntity.Type;

export const OtherEntity = pipe(
  BaseEntity,
  Schema.extend(
    Schema.Struct({
      state: Schema.String,
      entity_id: EntityId,
      attributes: Schema.Object,
    }),
  ),
);
export type OtherEntity = BaseEntity;

export const SensorEntity = pipe(
  BaseEntity,
  Schema.extend(
    Schema.Struct({
      entity_id: SensorEntityId,
    }),
  ),
);
export type SensorEntity = typeof SensorEntity.Type;

export const TemperatureSensorEntity = pipe(
  SensorEntity,
  Schema.extend(
    Schema.Struct({
      state: Schema.compose(Schema.NumberFromString, Temperature),
      attributes: Schema.Struct({
        state_class: Schema.Literal('measurement'),
        device_class: Schema.UndefinedOr(
          Schema.NullOr(Schema.Literal('temperature')),
        ),
        unit_of_measurement: Schema.Literal('°C'),
        friendly_name: Schema.String,
      }),
    }),
  ),
);
export type TemperatureSensorEntity = typeof TemperatureSensorEntity.Type;

export const OperationalClimateMode = Schema.Literal('auto', 'heat', 'off');
export type OperationalClimateMode = typeof OperationalClimateMode.Type;

export const HassHvacAction = Schema.Literal('idle', 'heating');
export type HassHvacAction = typeof HassHvacAction.Type;

const BaseClimateAttributes = Schema.Struct({
  hvac_modes: Schema.Array(Schema.String),
  min_temp: Temperature,
  max_temp: Temperature,
  preset_modes: Schema.optional(Schema.Array(Schema.String)),
  preset_mode: Schema.optional(Schema.String),
  friendly_name: Schema.String,
  supported_features: Schema.Number,
  restored: Schema.optional(Schema.Boolean),
});

export const AvailableClimateEntity = pipe(
  BaseEntity,
  Schema.extend(
    Schema.Struct({
      entity_id: ClimateEntityId,
      state: OperationalClimateMode,
      attributes: pipe(
        BaseClimateAttributes,
        Schema.extend(
          Schema.Struct({
            current_temperature: Temperature,
            temperature: Temperature,
            hvac_action: Schema.optional(HassHvacAction),
          }),
        ),
      ),
    }),
  ),
);
export type AvailableClimateEntity = typeof AvailableClimateEntity.Type;

export const UnavailableClimateEntity = pipe(
  BaseEntity,
  Schema.extend(
    Schema.Struct({
      entity_id: ClimateEntityId,
      state: Schema.Literal('unavailable'),
      attributes: Schema.Struct({
        friendly_name: Schema.String,
      }).pipe(
        Schema.extend(
          Schema.Record({ key: Schema.String, value: Schema.Unknown }),
        ),
      ),
    }),
  ),
);
export type UnavailableClimateEntity = typeof UnavailableClimateEntity.Type;

export const ClimateEntity = Schema.Union(
  AvailableClimateEntity,
  UnavailableClimateEntity,
);
export type ClimateEntity = typeof ClimateEntity.Type;

export const ClimateMode = Schema.Union(
  OperationalClimateMode,
  Schema.Literal('unavailable'),
);
export type ClimateMode = typeof ClimateMode.Type;

export const ButtonPressEventEntity = pipe(
  BaseEntity,
  Schema.extend(
    Schema.Struct({
      entity_id: EventEntityId,
      state: Schema.DateFromString,
      attributes: Schema.Struct({
        friendly_name: Schema.String,
      }),
    }),
  ),
);
export type ButtonPressEventEntity = typeof ButtonPressEventEntity.Type;

export const InputButtonEntity = pipe(
  BaseEntity,
  Schema.extend(
    Schema.Struct({
      entity_id: InputButtonEntityId,
      state: Schema.Date,
      attributes: Schema.Struct({
        friendly_name: Schema.String,
      }),
    }),
  ),
);
export type InputButtonEntity = typeof InputButtonEntity.Type;

export const GoodnightEventEntity = Schema.Union(
  InputButtonEntity,
  ButtonPressEventEntity,
);
export type GoodnightEventEntity = typeof GoodnightEventEntity.Type;

export const HomeAssistantEntity = Schema.Union(
  TemperatureSensorEntity,
  GoodnightEventEntity,
  ClimateEntity,
  OtherEntity,
);
export type HomeAssistantEntity = typeof HomeAssistantEntity.Type;

export const isSchema =
  <A, I>(schema: Schema.Schema<A, I>) =>
  (e: unknown): e is A =>
    Schema.is(schema)(e);
