import {
  HttpBody,
  HttpClient,
  HttpClientError,
  HttpClientRequest,
  HttpClientResponse,
} from '@effect/platform';
import { Schema } from '@effect/schema';
import { ParseError } from '@effect/schema/ParseResult';
import {
  ClimateEntityId,
  ClimateMode,
  HomeAssistantEntity,
  Temperature,
} from '@home-automation/deep-heating-types';
import { Config, Context, Effect, Layer, Runtime } from 'effect';
import { pipe } from 'effect/Function';
import { Observable, from, timer } from 'rxjs';
import { mergeAll, shareReplay, switchMap, throttleTime } from 'rxjs/operators';

export class HomeAssistantConfig extends Context.Tag('HomeAssistantConfig')<
  HomeAssistantConfig,
  {
    readonly url: string;
    readonly token: string;
  }
>() {}

export const HomeAssistantConfigLive = Layer.effect(
  HomeAssistantConfig,
  pipe(
    Config.all([
      pipe(
        Config.string('SUPERVISOR_URL'),
        Config.withDefault('http://supervisor'),
      ),
      Config.string('SUPERVISOR_TOKEN'),
    ]),
    Effect.map(([url, token]) => ({ url, token })),
  ),
);

export class HomeAssistantApi extends Context.Tag('HomeAssistantApi')<
  HomeAssistantApi,
  {
    getStates: () => Effect.Effect<
      unknown,
      HttpClientError.HttpClientError | ParseError
    >;
    setTemperature: (
      entityId: ClimateEntityId,
      targetTemperature: Temperature,
    ) => Effect.Effect<
      { entityId: ClimateEntityId; targetTemperature: Temperature },
      HttpClientError.HttpClientError | HttpBody.HttpBodyError
    >;
    setHvacMode: (
      entityId: ClimateEntityId,
      mode: ClimateMode,
    ) => Effect.Effect<
      { entityId: ClimateEntityId; mode: ClimateMode },
      HttpClientError.HttpClientError | HttpBody.HttpBodyError
    >;
  }
>() {}

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
                HttpClientRequest.get(url, {
                  headers: { Authorization: `Bearer ${token}` },
                }),
              ),
              Effect.flatMap((request) =>
                pipe(
                  request,
                  HttpClient.fetchOk,
                  Effect.withSpan('fetch_states'),
                ),
              ),
              Effect.flatMap(HttpClientResponse.schemaBodyJson(Schema.Unknown)),
              Effect.scoped,
            ),
          ),
        setTemperature: (entityId: ClimateEntityId, temperature: Temperature) =>
          pipe(
            url + '/api/services/climate/set_temperature',
            (url) => HttpClientRequest.post(url),
            HttpClientRequest.setHeader('Authorization', `Bearer ${token}`),
            HttpClientRequest.jsonBody({ entity_id: entityId, temperature }),
            Effect.flatMap(HttpClient.fetchOk),
            Effect.withSpan('set_temperature'),
            Effect.map(() => ({ entityId, targetTemperature: temperature })),
            Effect.scoped,
          ),
        setHvacMode: (entityId: ClimateEntityId, mode: ClimateMode) =>
          pipe(
            url + '/api/services/climate/set_hvac_mode',
            (url) => HttpClientRequest.post(url),
            HttpClientRequest.setHeader('Authorization', `Bearer ${token}`),
            HttpClientRequest.jsonBody({
              entity_id: entityId,
              hvac_mode: mode,
            }),
            Effect.flatMap(HttpClient.fetchOk),
            Effect.withSpan('set_hvac_mode'),
            Effect.map(() => ({ entityId, mode })),
            Effect.scoped,
          ),
      }),
    ),
  ),
);

export const HomeAssistantApiTest = (
  states: Effect.Effect<unknown, HttpClientError.HttpClientError | ParseError>,
) =>
  Layer.effect(
    HomeAssistantApi,
    Effect.succeed({
      getStates: () => states,
      setTemperature: (entityId: ClimateEntityId, temperature: Temperature) =>
        Effect.succeed({ entityId, targetTemperature: temperature }),
      setHvacMode: (entityId: ClimateEntityId, mode: ClimateMode) =>
        Effect.succeed({ entityId, mode }),
    }),
  );

export const getEntities = pipe(
  HomeAssistantApi,
  Effect.flatMap((api) =>
    pipe(
      api.getStates(),
      Effect.map(Schema.decodeUnknownSync(Schema.Array(HomeAssistantEntity))),
      Effect.withLogSpan(`fetch_entities`),
    ),
  ),
);

const refreshIntervalMilliseconds = 60 * 1000;

export const getEntityUpdates = (
  runtime: Runtime.Runtime<HomeAssistantApi>,
): Observable<HomeAssistantEntity> =>
  timer(0, refreshIntervalMilliseconds).pipe(
    throttleTime(refreshIntervalMilliseconds),
    switchMap(() => from(pipe(getEntities, Runtime.runPromise(runtime)))),
    mergeAll(),
    shareReplay(1),
  );
