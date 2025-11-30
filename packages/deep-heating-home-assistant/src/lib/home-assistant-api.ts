import {
  HttpClient,
  HttpClientRequest,
  HttpClientResponse,
} from '@effect/platform';
import { Duration, Schedule, Schema, Stream } from 'effect';
import {
  ClimateEntityId,
  HomeAssistantEntity,
  OperationalClimateMode,
  Temperature,
} from '@home-automation/deep-heating-types';
import { Config, Context, Effect, Layer } from 'effect';
import { pipe } from 'effect/Function';
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

const supervisorUrlConfig = pipe(
  'SUPERVISOR_URL',
  Config.string,
  Config.withDefault('http://supervisor'),
);

export const HomeAssistantConfigLive = Layer.effect(
  HomeAssistantConfig,
  pipe(
    [supervisorUrlConfig, Config.string('SUPERVISOR_TOKEN')],
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

const createHomeAssistantApi =
  (config: { readonly url: string; readonly token: string }) =>
  (httpClient: HttpClient.HttpClient) => {
    const client = httpClient.pipe(HttpClient.filterStatusOk);
    const { url, token } = config;

    const parseStatesResponse = HttpClientResponse.schemaBodyJson(
      Schema.Unknown,
    );

    return {
      getStates: () =>
        pipe(
          client.get(url + '/api/states', {
            headers: { Authorization: `Bearer ${token}` },
          }),
          Effect.withSpan('fetch_states'),
          Effect.flatMap(parseStatesResponse),
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
  };

const buildApiWithHttpClient = (
  config: Context.Tag.Service<typeof HomeAssistantConfig>,
) => pipe(HttpClient.HttpClient, Effect.map(createHomeAssistantApi(config)));

export const HomeAssistantApiLive = Layer.effect(
  HomeAssistantApi,
  pipe(HomeAssistantConfig, Effect.flatMap(buildApiWithHttpClient)),
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

const decodeEntitiesFromStates = (
  api: Context.Tag.Service<typeof HomeAssistantApi>,
) =>
  pipe(
    api.getStates(),
    Effect.map(Schema.decodeUnknownSync(Schema.Array(HomeAssistantEntity))),
    Effect.withLogSpan(`fetch_entities`),
  );

/**
 * Fetches all entities from Home Assistant and decodes them.
 * Requires HomeAssistantApi to be provided via Layer.
 */
export const getEntities: Effect.Effect<
  readonly HomeAssistantEntity[],
  HomeAssistantConnectionError,
  HomeAssistantApi
> = pipe(HomeAssistantApi, Effect.flatMap(decodeEntitiesFromStates));

const refreshInterval = Duration.minutes(1);

/**
 * Effect Stream that polls Home Assistant for entity updates.
 * Emits each entity individually, flattening the arrays from each poll.
 * Retries with exponential backoff on connection failures.
 *
 * Requires HomeAssistantApi to be provided via Layer at the composition root.
 */
export const getEntityUpdatesStream: Stream.Stream<
  HomeAssistantEntity,
  HomeAssistantConnectionError,
  HomeAssistantApi
> = pipe(
  HomeAssistantApi,
  Effect.flatMap(decodeEntitiesFromStates),
  Stream.fromEffect,
  Stream.flatMap(Stream.fromIterable),
  Stream.repeat(Schedule.fixed(refreshInterval)),
  Stream.retry(Schedule.exponential(Duration.seconds(1), 2)),
);
