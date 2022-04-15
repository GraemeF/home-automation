import { DateTime } from 'luxon';
import superagent from 'superagent';
import { Dictionary } from '@home-automation/dictionary';
import { SensorUpdate } from '@home-automation/deep-heating-types';

// eslint-disable-next-line @typescript-eslint/no-non-null-assertion
const ip = process.env['HUE_IP']!;
// eslint-disable-next-line @typescript-eslint/no-non-null-assertion
const username = process.env['HUE_USERNAME']!;

export const getSensors = async (): Promise<Dictionary<string, SensorUpdate>> =>
  (await superagent.get(`http://${ip}/api/${username}/sensors`)).body;

export const parseHueTime = (hueTime: string): DateTime =>
  DateTime.fromISO(hueTime, {
    zone: 'utc',
  }).toLocal();
