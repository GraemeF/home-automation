import { Schema } from 'effect';
import {
  AvailableClimateEntity,
  ClimateEntity,
  ClimateEntityId,
  HeatingUpdate,
  Home,
  HomeAssistantEntity,
  OperationalClimateMode,
  Temperature,
  TrvUpdate,
  isSchema,
} from '@home-automation/deep-heating-types';
import { shareReplayLatestByKey } from '@home-automation/rxx';
import debug from 'debug';
import { Effect, Option, pipe } from 'effect';
import { isNotNull } from 'effect/Predicate';
import { Observable } from 'rxjs';
import { filter, map, tap } from 'rxjs/operators';
import { HomeAssistantApi } from '../home-assistant-api';

const log = debug('deep-heating:ha-climate');

const decodeClimateEntityId = Schema.decodeSync(ClimateEntityId);
const heatingEntityId = decodeClimateEntityId('climate.main');

const isAvailableClimateEntity = (
  entity: ClimateEntity,
): entity is AvailableClimateEntity => entity.state !== 'unavailable';

export const getTrvApiUpdates =
  (home: Home) =>
  (p$: Observable<ClimateEntity>): Observable<TrvUpdate> =>
    p$.pipe(
      filter((entity) => entity.entity_id !== home.heatingId),
      tap((entity) => {
        if (!isAvailableClimateEntity(entity)) {
          log(
            '[%s] ⚠ FILTERED: state=%s (unavailable)',
            entity.entity_id,
            entity.state,
          );
        }
      }),
      filter(isAvailableClimateEntity),
      map((response: AvailableClimateEntity) => {
        const room = home.rooms.find((room) =>
          room.climateEntityIds.includes(response.entity_id),
        );
        const result = pipe(
          room,
          Option.fromNullable,
          Option.flatMap((room) => room.schedule),
          Option.map((schedule) => ({
            climateEntityId: response.entity_id,
            name: response.attributes.friendly_name,
            deviceType: 'trv',
            state: {
              temperature: {
                temperature: response.attributes.current_temperature,
                time: response.last_updated,
              },
              target: response.attributes.temperature,
              mode: response.state,
              isHeating: response.attributes.hvac_action === 'heating',
              schedule,
            },
          })),
          Option.getOrNull,
        );
        if (result === null) {
          log(
            '[%s] ⚠ FILTERED: room=%s has no schedule',
            response.entity_id,
            room?.name ?? 'unknown',
          );
        }
        return result;
      }),
      filter(isNotNull),
      tap((x) => {
        log(
          '[%s] ✓ TRV update received: mode=%s, target=%d',
          x.climateEntityId,
          x.state.mode,
          x.state.target,
        );
      }),
      shareReplayLatestByKey((x) => x.climateEntityId),
    );

export const getHeatingApiUpdates = (
  p$: Observable<ClimateEntity>,
): Observable<HeatingUpdate> =>
  p$.pipe(
    filter((entity) => entity.entity_id === heatingEntityId),
    filter(isAvailableClimateEntity),
    map((response: AvailableClimateEntity) => ({
      heatingId: response.entity_id,
      name: response.attributes.friendly_name,
      deviceType: 'trv',
      state: {
        temperature: {
          temperature: response.attributes.current_temperature,
          time: response.last_updated,
        },
        target: response.attributes.temperature,
        mode: response.state,
        isHeating: response.attributes.hvac_action === 'heating',
      },
    })),
    shareReplayLatestByKey((x) => x.heatingId),
  );

export const getClimateEntityUpdates = (
  entityUpdates$: Observable<HomeAssistantEntity>,
) => entityUpdates$.pipe(filter(isSchema(ClimateEntity)));

export const setClimateEntityTemperature = (
  entityId: ClimateEntityId,
  targetTemperature: Temperature,
) =>
  pipe(
    HomeAssistantApi,
    Effect.flatMap((api) => api.setTemperature(entityId, targetTemperature)),
  );

export const setClimateEntityMode = (
  entityId: ClimateEntityId,
  mode: OperationalClimateMode,
) =>
  pipe(
    HomeAssistantApi,
    Effect.flatMap((api) => api.setHvacMode(entityId, mode)),
  );
