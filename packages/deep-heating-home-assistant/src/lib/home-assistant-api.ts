import {
  HttpClient,
  HttpClientRequest,
  HttpClientResponse,
} from '@effect/platform';
import { Schema } from 'effect';
import {
  ClimateEntityId,
  HomeAssistantEntity,
  OperationalClimateMode,
  Temperature,
} from '@home-automation/deep-heating-types';
import { Config, Context, Effect, Layer, Runtime } from 'effect';
import { pipe } from 'effect/Function';
import { Observable, from, timer } from 'rxjs';
import { mergeAll, shareReplay, switchMap, throttleTime } from 'rxjs/operators';
import {
  HomeAssistantConnectionError,
  SetHvacModeError,
  SetTemperatureError,
} from './errors';

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
    [
      pipe(
        'SUPERVISOR_URL',
        Config.string,
        Config.withDefault('http://supervisor'),
      ),
      Config.string('SUPERVISOR_TOKEN'),
    ],
    Config.all,
    Effect.map(([url, token]) => ({ url, token })),
  ),
);

export class HomeAssistantApi extends Context.Tag('HomeAssistantApi')<
  HomeAssistantApi,
  {
    readonly getStates: () => Effect.Effect<
      unknown,
      HomeAssistantConnectionError
    >;
    readonly setTemperature: (
      entityId: ClimateEntityId,
      targetTemperature: Temperature,
    ) => Effect.Effect<
      {
        readonly entityId: ClimateEntityId;
        readonly targetTemperature: Temperature;
      },
      SetTemperatureError
    >;
    readonly setHvacMode: (
      entityId: ClimateEntityId,
      mode: OperationalClimateMode,
    ) => Effect.Effect<
      {
        readonly entityId: ClimateEntityId;
        readonly mode: OperationalClimateMode;
      },
      SetHvacModeError
    >;
  }
>() {}

export const HomeAssistantApiLive = Layer.effect(
  HomeAssistantApi,
  Effect.gen(function* () {
    const { url, token } = yield* HomeAssistantConfig;
    const httpClient = yield* HttpClient.HttpClient;
    const client = httpClient.pipe(HttpClient.filterStatusOk);

    return {
      getStates: () =>
        pipe(
          client.get(url + '/api/states', {
            headers: { Authorization: `Bearer ${token}` },
          }),
          Effect.withSpan('fetch_states'),
          Effect.flatMap(HttpClientResponse.schemaBodyJson(Schema.Unknown)),
          Effect.scoped,
          Effect.mapError(
            (cause) =>
              new HomeAssistantConnectionError({
                message: 'Failed to fetch states from Home Assistant',
                cause,
              }),
          ),
        ),
      setTemperature: (entityId: ClimateEntityId, temperature: Temperature) =>
        pipe(
          url + '/api/services/climate/set_temperature',
          HttpClientRequest.post,
          HttpClientRequest.setHeader('Authorization', `Bearer ${token}`),
          HttpClientRequest.bodyJson({ entity_id: entityId, temperature }),
          Effect.flatMap(client.execute),
          Effect.withSpan('set_temperature'),
          Effect.as({ entityId, targetTemperature: temperature }),
          Effect.scoped,
          Effect.mapError(
            (cause) =>
              new SetTemperatureError({
                entityId,
                targetTemperature: temperature,
                cause,
              }),
          ),
        ),
      setHvacMode: (entityId: ClimateEntityId, mode: OperationalClimateMode) =>
        pipe(
          url + '/api/services/climate/set_hvac_mode',
          HttpClientRequest.post,
          HttpClientRequest.setHeader('Authorization', `Bearer ${token}`),
          HttpClientRequest.bodyJson({
            entity_id: entityId,
            hvac_mode: mode,
          }),
          Effect.flatMap(client.execute),
          Effect.withSpan('set_hvac_mode'),
          Effect.as({ entityId, mode }),
          Effect.scoped,
          Effect.mapError(
            (cause) =>
              new SetHvacModeError({
                entityId,
                mode,
                cause,
              }),
          ),
        ),
    };
  }),
);

export const HomeAssistantApiTest = (
  states: Effect.Effect<unknown, HomeAssistantConnectionError>,
) =>
  Layer.effect(
    HomeAssistantApi,
    Effect.succeed({
      getStates: () => states,
      setTemperature: (entityId: ClimateEntityId, temperature: Temperature) =>
        Effect.succeed({ entityId, targetTemperature: temperature }),
      setHvacMode: (entityId: ClimateEntityId, mode: OperationalClimateMode) =>
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
