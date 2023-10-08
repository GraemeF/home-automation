import { HttpClientError } from '@effect/platform/Http/ClientError';
import { HassState } from './climate/climateEntity';
import * as HttpClient from '@effect/platform/HttpClient';
import * as Schema from '@effect/schema/Schema';
import { Config, Context, Effect, Layer } from 'effect';
import { pipe } from 'effect/Function';
import { Tag } from 'effect/Context';
import { ParseError } from '@effect/schema/ParseResult';
import { Temperature } from '@home-automation/deep-heating-types';
import { EntityId } from './entity';

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
  setHvacMode: (
    entityId: EntityId,
    mode: HassState
  ) => Effect.Effect<
    HomeAssistantConfig,
    HttpClientError,
    { readonly ok: boolean }
  >;
}

export const HomeAssistantApi = Tag<HomeAssistantApi>();

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
              pipe(request, HttpClient.client.fetchOk())
            ),
            Effect.withSpan('set_temperature'),
            Effect.match({
              onSuccess: () => ({ ok: true }),
              onFailure: (error) => ({ ok: false }),
            })
          )
        )
      ),
    setHvacMode: (entityId: EntityId, mode: HassState) =>
      pipe(
        HomeAssistantConfig,
        Effect.flatMap(({ url, token }) =>
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
      setHvacMode: () => Effect.succeed({ ok: true }),
    })
  );
