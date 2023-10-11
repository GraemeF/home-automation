import * as Schema from '@effect/schema/Schema';
import { Temperature } from '@home-automation/deep-heating-types';
import { Effect, Runtime } from 'effect';
import { pipe } from 'effect/Function';
import { Observable, from, timer } from 'rxjs';
import { mergeAll, shareReplay, switchMap, throttleTime } from 'rxjs/operators';
import { HomeAssistantApi } from './home-assistant-api';

export const EntityId = pipe(
  Schema.string,
  Schema.nonEmpty(),
  Schema.brand('EntityId')
);
export type EntityId = Schema.Schema.To<typeof EntityId>;

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

export const SensorEntityId = pipe(
  EntityId,
  Schema.startsWith('sensor.'),
  Schema.brand('SensorEntityId')
);
export type SensorEntityId = Schema.Schema.To<typeof SensorEntityId>;

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

export const HassState = Schema.literal('auto', 'heat', 'off');
export type HassState = Schema.Schema.To<typeof HassState>;

export const HassHvacAction = Schema.literal('idle', 'heating');
export type HassHvacAction = Schema.Schema.To<typeof HassHvacAction>;

export const ClimateEntityId = pipe(
  EntityId,
  Schema.startsWith('climate.'),
  Schema.brand('ClimateEntityId')
);
export type ClimateEntityId = Schema.Schema.To<typeof ClimateEntityId>;

export const ClimateEntity = pipe(
  BaseEntity,
  Schema.extend(
    Schema.struct({
      entity_id: ClimateEntityId,
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

export const EventEntityId = pipe(
  EntityId,
  Schema.startsWith('event.'),
  Schema.brand('EventEntityId')
);
export type EventEntityId = Schema.Schema.To<typeof EventEntityId>;

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

export const getEntities = pipe(
  HomeAssistantApi,
  Effect.flatMap((api) =>
    pipe(
      api.getStates(),
      Effect.map(Schema.parseSync(Schema.array(HomeAssistantEntity))),
      Effect.withLogSpan(`fetch_entities`)
    )
  )
);

const refreshIntervalMilliseconds = 60 * 1000;

export const getEntityUpdates = (
  runtime: Runtime.Runtime<HomeAssistantApi>
): Observable<HomeAssistantEntity> =>
  timer(0, refreshIntervalMilliseconds).pipe(
    throttleTime(refreshIntervalMilliseconds),
    switchMap(() => from(pipe(Runtime.runPromise(runtime)(getEntities)))),
    mergeAll(),
    shareReplay(1)
  );
