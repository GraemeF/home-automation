import { DateTime } from 'luxon';
import * as request from 'superagent';
import { Dictionary } from '@home-automation/dictionary';
import { SensorUpdate } from '@home-automation/deep-heating-types';

export const getSensors = async (): Promise<Dictionary<string, SensorUpdate>> =>
  (
    await request.get(
      `http://${process.env['HUE_BRIDGE']}/api/${process.env['HUE_USERNAME']}/sensors`
    )
  ).body;

export const parseHueTime = (hueTime: string): DateTime =>
  DateTime.fromISO(hueTime, {
    zone: 'utc',
  }).toLocal();
