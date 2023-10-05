import { DateTime } from 'luxon';
import debug from 'debug';
import { login_srp } from './hive-login';

import * as request from 'superagent';

import * as jwt from 'jsonwebtoken';
import {
  TrvModeValue,
  WeekHeatingSchedule,
} from '@home-automation/deep-heating-types';
import { JwtPayload } from 'jsonwebtoken';

const log = debug('hive-api');

interface Token {
  token: string;
  expiryTime: DateTime;
}

export interface HiveApiAccess {
  idToken: Token;
  endpoint: string;
}

function decodeToken(token: string) {
  const expiryTime = DateTime.fromSeconds(
    (jwt.decode(token) as JwtPayload).exp
  );
  return {
    token: token,
    expiryTime: expiryTime,
  };
}

export interface HiveDevice {
  id: string;
  type: string;
  name: string;
}

export interface HiveProduct {
  id: string;
  type: string;
  name: string;
}

interface DeviceResponse {
  id: string;
  type: string;
  state: { name: string };
}

interface HeatableProps {
  temperature: number;
  working: boolean;
}

interface HotWaterProps {
  working: boolean;
}

type TrvControlProps = HeatableProps;
type HeatingProps = HeatableProps;

interface HeatableState {
  name: string;
  mode: TrvModeValue;
  target: number;
  schedule: WeekHeatingSchedule;
}

type HeatingState = HeatableState;
type HiveTrvControlState = HeatableState;

interface CommonProductResponse<TProps, TState> {
  id: string;
  type: string;
  props: TProps;
  state: TState;
}

interface SenseProductResponse extends CommonProductResponse<unknown, unknown> {
  type: 'sense';
}

export interface TrvControlProductResponse
  extends CommonProductResponse<TrvControlProps, HiveTrvControlState> {
  type: 'trvcontrol';
}

interface HotWaterProductResponse
  extends CommonProductResponse<HotWaterProps, unknown> {
  type: 'hotwater';
}

export interface HeatingProductResponse
  extends CommonProductResponse<HeatingProps, HeatingState> {
  type: 'heating';
}

export type ProductResponse =
  | SenseProductResponse
  | TrvControlProductResponse
  | HotWaterProductResponse
  | HeatingProductResponse;

export interface HiveResult {
  ok: boolean;
  body?: Record<string, unknown>;
}

export async function login(): Promise<HiveApiAccess> {
  const response = await login_srp(
    // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
    process.env['HIVE_USERNAME']!,
    // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
    process.env['HIVE_PASSWORD']!
  );

  return {
    idToken: decodeToken(response.credentials.IdToken),
    endpoint: 'https://beekeeper-uk.hivehome.com/1.0',
  };
}

export async function getDevices(
  apiAccess: HiveApiAccess
): Promise<HiveDevice[]> {
  const response: DeviceResponse[] = await getResponse(apiAccess, '/devices');
  return response.map((deviceResponse) => ({
    id: deviceResponse.id,
    type: deviceResponse.type,
    name: deviceResponse.state.name,
  }));
}

async function getResponse(apiAccess: HiveApiAccess, path: string) {
  const url = apiAccess.endpoint + path;
  try {
    return (
      await request.get(url).auth(apiAccess.idToken.token, { type: 'bearer' })
    ).body;
  } catch (e) {
    log(`Failed to GET ${path}:`, e.message, e.response.text);
    return null;
  }
}

export const getProducts = (
  apiAccess: HiveApiAccess
): Promise<ProductResponse[] | null> => getResponse(apiAccess, '/products');

export async function setTrv(
  apiAccess: HiveApiAccess,
  trvId: string,
  mode?: TrvModeValue,
  targetTemperature?: number
): Promise<{
  trvId: string;
  mode?: TrvModeValue;
  targetTemperature?: number;
  result: { ok: boolean; body: Record<string, unknown> | undefined };
}> {
  const url = `${apiAccess.endpoint}/nodes/trvcontrol/${trvId}`;
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
  apiAccess: HiveApiAccess,
  heatingId: string,
  mode?: string,
  targetTemperature?: number
): Promise<{
  heatingId: string;
  mode?: string;
  targetTemperature?: number;
  result: HiveResult;
}> {
  let result: HiveResult;
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
