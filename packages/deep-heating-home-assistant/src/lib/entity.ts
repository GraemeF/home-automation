import * as Schema from '@effect/schema/Schema';
import { pipe } from 'effect/Function';

export const EntityId = pipe(
  Schema.string,
  Schema.nonEmpty(),
  Schema.brand('EntityId')
);
export type EntityId = Schema.Schema.To<typeof EntityId>;

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
