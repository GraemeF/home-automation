import * as Schema from '@effect/schema/Schema';
import { pipe } from 'effect/Function';

export const EntityId = pipe(
  Schema.string,
  Schema.nonEmpty(),
  Schema.brand('EntityId')
);
export type EntityId = Schema.Schema.To<typeof EntityId>;

export const Temperature = pipe(
  Schema.number,
  Schema.between(-20, 60),
  Schema.brand('ºC')
);
export type Temperature = Schema.Schema.To<typeof Temperature>;

export const HomeAssistantEntity = Schema.struct({
  state: Schema.string,
  entity_id: EntityId,
  last_changed: pipe(Schema.string, Schema.dateFromString),
  last_updated: pipe(Schema.string, Schema.dateFromString),
  context: Schema.struct({
    id: Schema.string,
    parent_id: Schema.optional(Schema.nullable(Schema.string)),
    user_id: Schema.optional(Schema.nullable(Schema.string)),
  }),
  attributes: Schema.readonlyMap(Schema.string, Schema.unknown),
});
export type HomeAssistantEntity = Schema.Schema.To<typeof HomeAssistantEntity>;

export const HassState = Schema.literal('auto', 'heat', 'off');
export type HassState = Schema.Schema.To<typeof HassState>;

export const HassHvacAction = Schema.literal('idle', 'heating');
export type HassHvacAction = Schema.Schema.To<typeof HassHvacAction>;

export const ClimateEntity = pipe(
  HomeAssistantEntity,
  Schema.omit('state'),
  Schema.omit('attributes'),
  Schema.extend(
    Schema.struct({
      state: HassState,
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
