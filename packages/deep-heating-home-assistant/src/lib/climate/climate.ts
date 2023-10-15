import * as Schema from '@effect/schema/Schema';
import {
  ClimateEntity,
  ClimateEntityId,
  ClimateMode,
  HeatingUpdate,
  Home,
  HomeAssistantEntity,
  Temperature,
  TrvUpdate,
} from '@home-automation/deep-heating-types';
import { shareReplayLatestByKey } from '@home-automation/rxx';
import { Effect, Option, pipe } from 'effect';
import { isNotNull } from 'effect/Predicate';
import { Observable } from 'rxjs';
import { filter, map } from 'rxjs/operators';
import { HomeAssistantApi } from '../home-assistant-api';

const heatingEntityId = Schema.decodeSync(ClimateEntityId)('climate.main');

export const getTrvApiUpdates =
  (home: Home) =>
  (p$: Observable<ClimateEntity>): Observable<TrvUpdate> =>
    p$.pipe(
      filter((entity) => entity.entity_id !== home.heatingId),
      map((response) =>
        pipe(
          home.rooms.find((room) =>
            room.climateEntityIds.includes(response.entity_id)
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
          Option.getOrNull
        )
      ),
      filter(isNotNull),
      shareReplayLatestByKey((x) => x.climateEntityId)
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
        mode: response.state,
        isHeating: response.attributes.hvac_action === 'heating',
      },
    })),
    shareReplayLatestByKey((x) => x.heatingId)
  );

export const getClimateEntityUpdates = (
  entityUpdates$: Observable<HomeAssistantEntity>
) => entityUpdates$.pipe(filter(Schema.is(ClimateEntity)));

export const setClimateEntityTemperature = (
  entityId: ClimateEntityId,
  targetTemperature: Temperature
) =>
  pipe(
    HomeAssistantApi,
    Effect.flatMap((api) => api.setTemperature(entityId, targetTemperature))
  );

export const setClimateEntityMode = (
  entityId: ClimateEntityId,
  mode: ClimateMode
) =>
  pipe(
    HomeAssistantApi,
    Effect.flatMap((api) => api.setHvacMode(entityId, mode))
  );
