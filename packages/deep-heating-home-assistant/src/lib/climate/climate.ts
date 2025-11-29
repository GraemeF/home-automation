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
import { Effect, Option, pipe } from 'effect';
import { isNotNull } from 'effect/Predicate';
import { Observable } from 'rxjs';
import { filter, map } from 'rxjs/operators';
import { HomeAssistantApi } from '../home-assistant-api';

const heatingEntityId = Schema.decodeSync(ClimateEntityId)('climate.main');

const isAvailableClimateEntity = (
  entity: ClimateEntity,
): entity is AvailableClimateEntity => entity.state !== 'unavailable';

export const getTrvApiUpdates =
  (home: Home) =>
  (p$: Observable<ClimateEntity>): Observable<TrvUpdate> =>
    p$.pipe(
      filter((entity) => entity.entity_id !== home.heatingId),
      filter(isAvailableClimateEntity),
      map((response: AvailableClimateEntity) =>
        pipe(
          home.rooms.find((room) =>
            room.climateEntityIds.includes(response.entity_id),
          ),
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
        ),
      ),
      filter(isNotNull),
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
