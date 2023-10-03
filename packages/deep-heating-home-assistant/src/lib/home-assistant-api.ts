import debug from 'debug';
import * as request from 'superagent';
import { TrvModeValue } from '@home-automation/deep-heating-types';
import { ClimateEntity } from './schema';
import { HttpClientError } from '@effect/platform/Http/ClientError';
import * as HttpClient from '@effect/platform/HttpClient';
import * as Schema from '@effect/schema/Schema';
import { Effect } from 'effect';
import { pipe } from 'effect/Function';

const log = debug('homeassistant-api');

// eslint-disable-next-line @typescript-eslint/no-non-null-assertion
const endpoint = process.env.HOMEASSISTANT_URL!;
// eslint-disable-next-line @typescript-eslint/no-non-null-assertion
const token = process.env.HOMEASSISTANT_TOKEN!;

type GetClimateEntitiesError = HttpClientError;

const getRequest = (url: string) =>
  pipe(
    url,
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
    Effect.tapBoth({
      onSuccess: () => Effect.log('OK'),
      onFailure: (error) =>
        Effect.log(`Error ${JSON.stringify(error, null, 2)}`),
    })
  );

export const getClimateEntities = pipe(
  endpoint + '/api/states',
  getRequest,
  Effect.flatMap(
    HttpClient.response.schemaBodyJson(Schema.array(ClimateEntity))
  ),
  Effect.map((states) =>
    states.filter((state) => state.entity_id.startsWith('climate.'))
  ),
  Effect.withLogSpan(`fetch_climate_entities`)
);

export async function setTrv(
  trvClimateEntityId: string,
  mode?: TrvModeValue,
  targetTemperature?: number
): Promise<{
  trvId: string;
  mode?: TrvModeValue;
  targetTemperature?: number;
  result: { ok: boolean; body: Record<string, unknown> | undefined };
}> {
  const url = `${endpoint}/nodes/trvcontrol/${trvId}`;
  const data: {
    mode?: TrvModeValue | undefined;
    target?: number | undefined;
  } = {};
  if (mode) data.mode = mode;
  if (targetTemperature) data.target = targetTemperature;

  let result;
  try {
    result = await request
      .post(url)
      .auth(apiAccess.idToken.token, { type: 'bearer' })
      .set('Content-Type', 'application/json')
      .send(data);
  } catch (e) {
    log(`Failed to set TRV ${data}:`, e.message, e.response.text);
    result = { ok: false };
  }
  return {
    trvId: trvId,
    mode: mode,
    targetTemperature: targetTemperature,
    result: result,
  };
}

export async function setHeating(
  apiAccess: HomeAssistantApiAccess,
  heatingId: string,
  mode?: string,
  targetTemperature?: number
): Promise<{
  heatingId: string;
  mode?: string;
  targetTemperature?: number;
  result: HomeAssistantResult;
}> {
  let result: HomeAssistantResult;
  const data = { mode: mode, target: targetTemperature };
  try {
    result = await request
      .post(`${apiAccess.endpoint}/nodes/heating/${heatingId}`)
      .auth(apiAccess.idToken.token, { type: 'bearer' })
      .set('Content-Type', 'application/json')
      .send(data);
  } catch (e) {
    log(`Failed to set heating ${data}:`, e.message, e.response.text);
    result = { ok: false };
  }
  return {
    heatingId,
    mode,
    targetTemperature,
    result: result,
  };
}
