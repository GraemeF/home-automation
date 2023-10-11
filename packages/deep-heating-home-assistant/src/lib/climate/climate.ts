import * as Schema from '@effect/schema/Schema';
import {
  HeatingUpdate,
  Home,
  SimpleDaySchedule,
  simpleToWeekSchedule,
  SimpleWeekSchedule,
  Temperature,
  TrvModeValue,
  TrvUpdate,
} from '@home-automation/deep-heating-types';
import { shareReplayLatestByKey } from '@home-automation/rxx';
import { Effect, pipe } from 'effect';
import { DateTime } from 'luxon';
import { Observable } from 'rxjs';
import { filter, map } from 'rxjs/operators';
import {
  ClimateEntity,
  ClimateEntityId,
  HassState,
  HomeAssistantEntity,
} from '../entity';
import { HomeAssistantApi } from '../home-assistant-api';

const heatingEntityId = Schema.decodeSync(ClimateEntityId)('climate.main');

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

const defaultDaySchedule = Schema.decodeSync(SimpleDaySchedule)({ '00:00': 7 });
const defaultSchedule: SimpleWeekSchedule = Schema.decodeSync(
  SimpleWeekSchedule
)({
  monday: defaultDaySchedule,
  tuesday: defaultDaySchedule,
  wednesday: defaultDaySchedule,
  thursday: defaultDaySchedule,
  friday: defaultDaySchedule,
  saturday: defaultDaySchedule,
  sunday: defaultDaySchedule,
});

export const getTrvApiUpdates =
  (home: Home) =>
  (p$: Observable<ClimateEntity>): Observable<TrvUpdate> =>
    p$.pipe(
      filter((entity) => entity.entity_id !== heatingEntityId),
      map((response) => ({
        trvId: response.entity_id,
        name: response.attributes.friendly_name,
        deviceType: 'trv',
        state: {
          temperature: {
            temperature: response.attributes.current_temperature,
            time: DateTime.fromJSDate(response.last_updated),
          },
          target: response.attributes.temperature,
          mode: hassStateToTrvModeValue(response.state),
          isHeating: response.attributes.hvac_action === 'heating',
          schedule: simpleToWeekSchedule(
            home.rooms.find((room) =>
              room.trvControlIds.includes(response.entity_id)
            )?.schedule ?? defaultSchedule
          ),
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
          time: DateTime.fromJSDate(response.last_updated),
        },
        target: response.attributes.temperature,
        mode: hassStateToTrvModeValue(response.state),
        isHeating: response.attributes.hvac_action === 'heating',
        schedule: simpleToWeekSchedule(defaultSchedule),
      },
    })),
    shareReplayLatestByKey((x) => x.heatingId)
  );

export const getClimateEntityUpdates = (
  entityUpdates$: Observable<HomeAssistantEntity>
) => entityUpdates$.pipe(filter(Schema.is(ClimateEntity)));

export const setClimateEntityTemperature = (
  entityId: ClimateEntityId,
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

export const setClimateEntityMode = (
  entityId: ClimateEntityId,
  mode: HassState
) =>
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
