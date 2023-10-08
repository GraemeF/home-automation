import * as Schema from '@effect/schema/Schema';
import { Temperature } from '@home-automation/deep-heating-types';
import { pipe } from 'effect/Function';
import { HomeAssistantEntity } from '../entity';

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
