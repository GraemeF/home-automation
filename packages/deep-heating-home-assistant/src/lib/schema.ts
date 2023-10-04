import * as Schema from '@effect/schema/Schema';
import { pipe } from 'effect/Function';

const EntityId = pipe(
  Schema.string,
  Schema.nonEmpty(),
  Schema.brand('EntityId')
);
type EntityId = Schema.Schema.To<typeof EntityId>;

const Temperature = pipe(
  Schema.number,
  Schema.between(-20, 60),
  Schema.brand('Temperature')
);
type Temperature = Schema.Schema.To<typeof Temperature>;

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

export const ClimateEntity = pipe(
  HomeAssistantEntity,
  Schema.omit('attributes'),
  Schema.extend(
    Schema.struct({
      attributes: Schema.struct({
        hvac_modes: Schema.array(Schema.string),
        min_temp: Temperature,
        max_temp: Temperature,
        preset_modes: Schema.optional(Schema.array(Schema.string)),
        current_temperature: Temperature,
        temperature: Temperature,
        hvac_action: Schema.optional(Schema.string),
        preset_mode: Schema.optional(Schema.string),
        friendly_name: Schema.string,
        supported_features: Schema.number,
      }),
    })
  )
);
export type ClimateEntity = Schema.Schema.To<typeof ClimateEntity>;
