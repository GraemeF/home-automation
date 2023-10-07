import { HttpClientError } from '@effect/platform/Http/ClientError';
import { ClimateEntity, EntityId } from './schema';
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

const getRequest = (path: string) =>
  pipe(
    HomeAssistantConfig,
    Effect.flatMap(({ url, token }) =>
      pipe(
        url + path,
        Effect.succeed,
        Effect.tap((url) => Effect.log(`Fetching ${url}`)),
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
        Effect.flatMap(HttpClient.response.schemaBodyJson(Schema.unknown)),
        Effect.tapBoth({
          onSuccess: () => Effect.log('OK'),
          onFailure: (error) =>
            Effect.log(`Error ${JSON.stringify(error, null, 2)}`),
        })
      )
    )
  );

export interface HomeAssistantApi {
  getStates: () => Effect.Effect<
    HomeAssistantConfig,
    HttpClientError | ParseError,
    unknown
  >;
  setState: <T>(
    entityId: EntityId,
    state: T
  ) => Effect.Effect<
    HomeAssistantConfig,
    HttpClientError | ParseError | Error,
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
    getStates: () => pipe('/api/states', getRequest),
    setState: () => Effect.fail(new Error('Not implemented')),
  })
);

export const HomeAssistantApiTest = (
  states: Effect.Effect<never, HttpClientError | ParseError, unknown>
) =>
  Layer.effect(
    HomeAssistantApi,
    Effect.succeed({
      getStates: () => states,
      setState: () => Effect.fail(new Error('Not implemented')),
    })
  );
