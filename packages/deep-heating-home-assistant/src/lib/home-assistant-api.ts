import { BodyError } from '@effect/platform/Http/Body';
import { HttpClientError } from '@effect/platform/Http/ClientError';
import * as HttpClient from '@effect/platform/HttpClient';
import { ParseError } from '@effect/schema/ParseResult';
import * as Schema from '@effect/schema/Schema';
import {
  ClimateEntityId,
  ClimateMode,
  HomeAssistantEntity,
  Temperature,
} from '@home-automation/deep-heating-types';
import { Config, Context, Effect, Layer, Runtime } from 'effect';
import { Tag } from 'effect/Context';
import { pipe } from 'effect/Function';
import { Observable, from, timer } from 'rxjs';
import { mergeAll, shareReplay, switchMap, throttleTime } from 'rxjs/operators';

export interface HomeAssistantConfig {
  readonly url: string;
  readonly token: string;
}
export const HomeAssistantConfig = Context.Tag<HomeAssistantConfig>();

export const HomeAssistantConfigLive = Layer.effect(
  HomeAssistantConfig,
  pipe(
    Effect.config(
      Config.all([
        Config.string('HOMEASSISTANT_URL'),
        Config.string('HOMEASSISTANT_TOKEN'),
      ])
    ),
    Effect.map(([url, token]) => ({ url, token }))
  )
);

export interface HomeAssistantApi {
  getStates: () => Effect.Effect<never, HttpClientError | ParseError, unknown>;
  setTemperature: (
    entityId: ClimateEntityId,
    targetTemperature: Temperature
  ) => Effect.Effect<
    never,
    HttpClientError | BodyError,
    { entityId: ClimateEntityId; targetTemperature: Temperature }
  >;
  setHvacMode: (
    entityId: ClimateEntityId,
    mode: ClimateMode
  ) => Effect.Effect<
    never,
    HttpClientError | BodyError,
    { entityId: ClimateEntityId; mode: ClimateMode }
  >;
}

export const HomeAssistantApi = Tag<HomeAssistantApi>();

export const HomeAssistantApiLive = Layer.effect(
  HomeAssistantApi,
  pipe(
    HomeAssistantConfig,
    Effect.flatMap(({ url, token }) =>
      Effect.succeed({
        getStates: () =>
          pipe(
            pipe(
              url + '/api/states',
              Effect.succeed,
              Effect.map((url) =>
                HttpClient.request.get(url, {
                  headers: { Authorization: `Bearer ${token}` },
                })
              ),
              Effect.flatMap((request) =>
                pipe(
                  request,
                  HttpClient.client.fetchOk(),
                  Effect.withSpan('fetch_states')
                )
              ),
              Effect.flatMap(HttpClient.response.schemaBodyJson(Schema.unknown))
            )
          ),
        setTemperature: (entityId: ClimateEntityId, temperature: Temperature) =>
          pipe(
            url + '/api/services/climate/set_temperature',
            (url) => HttpClient.request.post(url),
            HttpClient.request.setHeader('Authorization', `Bearer ${token}`),
            HttpClient.request.jsonBody({ entity_id: entityId, temperature }),
            Effect.flatMap((request) =>
              pipe(request, HttpClient.client.fetchOk())
            ),
            Effect.withSpan('set_temperature'),
            Effect.map(() => ({ entityId, targetTemperature: temperature }))
          ),
        setHvacMode: (entityId: ClimateEntityId, mode: ClimateMode) =>
          pipe(
            url + '/api/services/climate/set_hvac_mode',
            (url) => HttpClient.request.post(url),
            HttpClient.request.setHeader('Authorization', `Bearer ${token}`),
            HttpClient.request.jsonBody({
              entity_id: entityId,
              hvac_mode: mode,
            }),
            Effect.flatMap((request) =>
              pipe(request, HttpClient.client.fetchOk())
            ),
            Effect.withSpan('set_hvac_mode'),
            Effect.map(() => ({ entityId, mode }))
          ),
      })
    )
  )
);

export const HomeAssistantApiTest = (
  states: Effect.Effect<never, HttpClientError | ParseError, unknown>
) =>
  Layer.effect(
    HomeAssistantApi,
    Effect.succeed({
      getStates: () => states,
      setTemperature: (entityId: ClimateEntityId, temperature: Temperature) =>
        Effect.succeed({ entityId, targetTemperature: temperature }),
      setHvacMode: (entityId: ClimateEntityId, mode: ClimateMode) =>
        Effect.succeed({ entityId, mode }),
    })
  );

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
