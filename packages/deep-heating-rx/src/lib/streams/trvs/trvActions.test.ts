import { describe, expect, it } from 'bun:test';
import { pipe, Schema } from 'effect';
import {
  ClimateEntityId,
  decodeTemperature,
} from '@home-automation/deep-heating-types';
import { DateTime } from 'luxon';
import { determineAction } from './trvActions';

describe('TRV action', () => {
  const daytime: DateTime = DateTime.fromISO('2020-01-01T12:00Z');
  const trvId = pipe(
    'climate.the_trv',
    Schema.decodeUnknownSync(ClimateEntityId),
  );

  it('off', () => {
    const action = determineAction(
      {
        climateEntityId: trvId,
        targetTemperature: decodeTemperature(20),
      },
      {
        climateEntityId: trvId,
        mode: 'off',
        source: 'Device',
        targetTemperature: decodeTemperature(7),
      },
      {
        climateEntityId: trvId,
        temperatureReading: {
          time: daytime.toJSDate(),
          temperature: decodeTemperature(10),
        },
      },
      {
        climateEntityId: trvId,
        scheduledTargetTemperature: decodeTemperature(18),
      },
    );

    expect(action).toBeNull();
  });

  it('should do something', () => {
    const action = determineAction(
      {
        targetTemperature: decodeTemperature(23),
        climateEntityId: trvId,
      },
      {
        climateEntityId: trvId,
        mode: 'heat',
        targetTemperature: decodeTemperature(18.5),
        source: 'Device',
      },
      {
        climateEntityId: trvId,
        temperatureReading: {
          temperature: decodeTemperature(21),
          time: daytime.toJSDate(),
        },
      },
      {
        climateEntityId: trvId,
        scheduledTargetTemperature: decodeTemperature(18),
      },
    );

    expect(action).toStrictEqual({
      mode: 'heat',
      targetTemperature: 23,
      climateEntityId: trvId,
    });
  });

  it('should not change from heat to auto', () => {
    const action = determineAction(
      {
        targetTemperature: decodeTemperature(23),
        climateEntityId: trvId,
      },
      {
        climateEntityId: trvId,
        mode: 'heat',
        targetTemperature: decodeTemperature(18.5),
        source: 'Device',
      },
      {
        climateEntityId: trvId,
        temperatureReading: {
          temperature: decodeTemperature(18.5),
          time: daytime.toJSDate(),
        },
      },
      {
        climateEntityId: trvId,
        scheduledTargetTemperature: decodeTemperature(23),
      },
    );

    expect(action).toStrictEqual({
      mode: 'heat',
      targetTemperature: 23,
      climateEntityId: trvId,
    });
  });

  it('should change from auto to heat', () => {
    const action = determineAction(
      {
        targetTemperature: decodeTemperature(18.5),
        climateEntityId: trvId,
      },
      {
        climateEntityId: trvId,
        mode: 'auto',
        targetTemperature: decodeTemperature(23),
        source: 'Device',
      },
      {
        climateEntityId: trvId,
        temperatureReading: {
          temperature: decodeTemperature(18.5),
          time: daytime.toJSDate(),
        },
      },
      {
        climateEntityId: trvId,
        scheduledTargetTemperature: decodeTemperature(23),
      },
    );

    expect(action).toStrictEqual({
      mode: 'heat',
      targetTemperature: 18.5,
      climateEntityId: trvId,
    });
  });

  it('should change heat target temperature', () => {
    const action = determineAction(
      {
        targetTemperature: decodeTemperature(18.5),
        climateEntityId: trvId,
      },
      {
        climateEntityId: trvId,
        mode: 'heat',
        targetTemperature: decodeTemperature(23),
        source: 'Device',
      },
      {
        climateEntityId: trvId,
        temperatureReading: {
          temperature: decodeTemperature(18.5),
          time: daytime.toJSDate(),
        },
      },
      {
        climateEntityId: trvId,
        scheduledTargetTemperature: decodeTemperature(23),
      },
    );

    expect(action).toStrictEqual({
      mode: 'heat',
      targetTemperature: 18.5,
      climateEntityId: trvId,
    });
  });
});
