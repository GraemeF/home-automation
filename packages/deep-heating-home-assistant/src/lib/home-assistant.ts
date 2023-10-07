import { from, Observable, timer } from 'rxjs';
import {
  getClimateEntities,
  HomeAssistantApi,
  HomeAssistantConfig,
} from './home-assistant-api';
import { shareReplay, switchMap, throttleTime, mergeAll } from 'rxjs/operators';
import { ClimateEntity, EntityId, HassState, Temperature } from './schema';
import { Effect, pipe, Runtime } from 'effect';
import { filter, map } from 'rxjs/operators';
import { shareReplayLatestByKey } from '@home-automation/rxx';
import {
  HeatingUpdate,
  TrvModeValue,
  TrvUpdate,
  WeekHeatingSchedule,
} from '@home-automation/deep-heating-types';
import * as Schema from '@effect/schema/Schema';

const heatingEntityId = Schema.decodeSync(EntityId)('climate.main');

const defaultSchedule: WeekHeatingSchedule = {
  monday: [
    {
      start: 450,
      value: {
        target: 20,
      },
    },
    {
      start: 480,
      value: {
        target: 20,
      },
    },
    {
      start: 1020,
      value: {
        target: 21,
      },
    },
    {
      start: 1140,
      value: {
        target: 21,
      },
    },
    {
      start: 1320,
      value: {
        target: 7,
      },
    },
  ],
  tuesday: [
    {
      start: 450,
      value: {
        target: 20,
      },
    },
    {
      start: 480,
      value: {
        target: 20,
      },
    },
    {
      start: 1020,
      value: {
        target: 21,
      },
    },
    {
      start: 1140,
      value: {
        target: 21,
      },
    },
    {
      start: 1320,
      value: {
        target: 7,
      },
    },
  ],
  wednesday: [
    {
      start: 450,
      value: {
        target: 20,
      },
    },
    {
      start: 480,
      value: {
        target: 20,
      },
    },
    {
      start: 1020,
      value: {
        target: 21,
      },
    },
    {
      start: 1140,
      value: {
        target: 21,
      },
    },
    {
      start: 1320,
      value: {
        target: 7,
      },
    },
  ],
  thursday: [
    {
      start: 450,
      value: {
        target: 20,
      },
    },
    {
      start: 480,
      value: {
        target: 20,
      },
    },
    {
      start: 1020,
      value: {
        target: 21,
      },
    },
    {
      start: 1140,
      value: {
        target: 21,
      },
    },
    {
      start: 1320,
      value: {
        target: 7,
      },
    },
  ],
  friday: [
    {
      start: 450,
      value: {
        target: 20,
      },
    },
    {
      start: 480,
      value: {
        target: 20,
      },
    },
    {
      start: 1020,
      value: {
        target: 21,
      },
    },
    {
      start: 1140,
      value: {
        target: 21,
      },
    },
    {
      start: 1425,
      value: {
        target: 7,
      },
    },
  ],
  saturday: [
    {
      start: 480,
      value: {
        target: 20,
      },
    },
    {
      start: 960,
      value: {
        target: 20,
      },
    },
    {
      start: 1260,
      value: {
        target: 21,
      },
    },
    {
      start: 1425,
      value: {
        target: 7,
      },
    },
  ],
  sunday: [
    {
      start: 480,
      value: {
        target: 20,
      },
    },
    {
      start: 960,
      value: {
        target: 20.5,
      },
    },
    {
      start: 1260,
      value: {
        target: 21,
      },
    },
    {
      start: 1320,
      value: {
        target: 7,
      },
    },
  ],
};

const hassStateToTrvModeValue: (state: HassState) => TrvModeValue = (state) => {
  switch (state) {
    case 'auto':
      return 'SCHEDULE';
    case 'heat':
      return 'MANUAL';
    case 'off':
      return 'OFF';
  }
};

export const getTrvApiUpdates = (
  p$: Observable<ClimateEntity>
): Observable<TrvUpdate> =>
  p$.pipe(
    filter((entity) => entity.entity_id !== heatingEntityId),
    map((response) => ({
      trvId: response.entity_id,
      name: response.attributes.friendly_name,
      deviceType: 'trv',
      state: {
        temperature: {
          temperature: response.attributes.current_temperature,
          time: response.last_updated,
        },
        target: response.attributes.temperature,
        mode: hassStateToTrvModeValue(response.state),
        isHeating: response.attributes.hvac_action === 'heating',
        schedule: defaultSchedule,
      },
    })),
    shareReplayLatestByKey((x) => x.trvId)
  );

export const getHeatingApiUpdates = (
  p$: Observable<ClimateEntity>
): Observable<HeatingUpdate> =>
  p$.pipe(
    filter((entity) => entity.entity_id === heatingEntityId),
    map((response) => ({
      heatingId: response.entity_id,
      name: response.attributes.friendly_name,
      deviceType: 'trv',
      state: {
        temperature: {
          temperature: response.attributes.current_temperature,
          time: response.last_updated,
        },
        target: response.attributes.temperature,
        mode: hassStateToTrvModeValue(response.state),
        isHeating: response.attributes.hvac_action === 'heating',
        schedule: defaultSchedule,
      },
    })),
    shareReplayLatestByKey((x) => x.heatingId)
  );

const refreshIntervalMilliseconds = 60 * 1000;

export const getClimateEntityUpdates = (
  runtime: Runtime.Runtime<HomeAssistantApi | HomeAssistantConfig>
): Observable<ClimateEntity> =>
  timer(0, refreshIntervalMilliseconds).pipe(
    throttleTime(refreshIntervalMilliseconds),
    switchMap(() =>
      from(pipe(Runtime.runPromise(runtime)(getClimateEntities)))
    ),
    mergeAll(),
    shareReplay(1)
  );

export const setClimateEntityTemperature = (
  entityId: EntityId,
  temperature: Temperature
) =>
  pipe(
    HomeAssistantApi,
    Effect.flatMap((api) => api.setTemperature(entityId, temperature)),
    Effect.match({
      onFailure: () => ({
        result: { ok: false },
        entityId,
        targetTemperature: temperature,
      }),
      onSuccess: () => ({
        result: { ok: true },
        entityId,
        targetTemperature: temperature,
      }),
    })
  );

export const setClimateEntityMode = (entityId: EntityId, mode: HassState) =>
  pipe(
    HomeAssistantApi,
    Effect.flatMap((api) => api.setHvacMode(entityId, mode)),
    Effect.match({
      onFailure: () => ({
        result: { ok: false },
        entityId,
        mode,
      }),
      onSuccess: () => ({
        result: { ok: true },
        entityId,
        mode,
      }),
    })
  );
