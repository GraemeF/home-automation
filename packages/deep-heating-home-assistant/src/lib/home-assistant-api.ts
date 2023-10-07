import { HttpClientError } from '@effect/platform/Http/ClientError';
import { ClimateEntity, EntityId, Temperature } from './schema';
import * as HttpClient from '@effect/platform/HttpClient';
import * as Schema from '@effect/schema/Schema';
import { Config, Context, Effect, Layer } from 'effect';
import { pipe } from 'effect/Function';
import { Tag } from 'effect/Context';
import { ParseError } from '@effect/schema/ParseResult';

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
  getStates: () => Effect.Effect<
    HomeAssistantConfig,
    HttpClientError | ParseError,
    unknown
  >;
  setTemperature: (
    entityId: EntityId,
    temperature: Temperature
  ) => Effect.Effect<
    HomeAssistantConfig,
    HttpClientError,
    { readonly ok: boolean }
  >;
}

export const HomeAssistantApi = Tag<HomeAssistantApi>();

export const getClimateEntities = pipe(
  HomeAssistantApi,
  Effect.flatMap((api) =>
    pipe(
      api.getStates(),
      Effect.flatMap(Schema.parse(Schema.array(Schema.any))),
      Effect.map((states) =>
        states.filter((state) => state['entity_id'].startsWith('climate.'))
      ),
      Effect.tap((states) =>
        Effect.log(`Found ${states.length} climate entities`)
      ),
      Effect.flatMap(Schema.decode(Schema.array(ClimateEntity))),
      Effect.withLogSpan(`fetch_climate_entities`)
    )
  )
);

export const HomeAssistantApiLive = Layer.effect(
  HomeAssistantApi,
  Effect.succeed({
    getStates: () =>
      pipe(
        HomeAssistantConfig,
        Effect.flatMap(({ url, token }) =>
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
        )
      ),
    setTemperature: (entityId: EntityId, temperature: Temperature) =>
      pipe(
        HomeAssistantConfig,
        Effect.flatMap(({ url, token }) =>
          pipe(
            url + '/api/services/climate/set_temperature',
            (url) => HttpClient.request.post(url),
            HttpClient.request.setHeader('Authorization', `Bearer ${token}`),
            HttpClient.request.jsonBody({ entity_id: entityId, temperature }),
            Effect.flatMap((request) =>
              pipe(
                request,
                HttpClient.client.fetchOk(),
                Effect.withSpan('set_state')
              )
            ),
            Effect.match({
              onSuccess: () => ({ ok: true }),
              onFailure: (error) => ({ ok: false }),
            })
          )
        )
      ),
  })
);

export const HomeAssistantApiTest = (
  states: Effect.Effect<never, HttpClientError | ParseError, unknown>
) =>
  Layer.effect(
    HomeAssistantApi,
    Effect.succeed({
      getStates: () => states,
      setTemperature: () => Effect.succeed({ ok: true }),
    })
  );
