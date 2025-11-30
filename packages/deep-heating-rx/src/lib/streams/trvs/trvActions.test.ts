import { describe, expect, it } from 'bun:test';
import { pipe, Schema } from 'effect';
import {
  ClimateEntityId,
  Temperature,
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
        targetTemperature: pipe(20, Schema.decodeUnknownSync(Temperature)),
      },
      {
        climateEntityId: trvId,
        mode: 'off',
        source: 'Device',
        targetTemperature: pipe(7, Schema.decodeUnknownSync(Temperature)),
      },
      {
        climateEntityId: trvId,
        temperatureReading: {
          time: daytime.toJSDate(),
          temperature: pipe(10, Schema.decodeUnknownSync(Temperature)),
        },
      },
      {
        climateEntityId: trvId,
        scheduledTargetTemperature: pipe(
          18,
          Schema.decodeUnknownSync(Temperature),
        ),
      },
    );

    expect(action).toBeNull();
  });

  it('should do something', () => {
    const action = determineAction(
      {
        targetTemperature: pipe(23, Schema.decodeUnknownSync(Temperature)),
        climateEntityId: trvId,
      },
      {
        climateEntityId: trvId,
        mode: 'heat',
        targetTemperature: pipe(18.5, Schema.decodeUnknownSync(Temperature)),
        source: 'Device',
      },
      {
        climateEntityId: trvId,
        temperatureReading: {
          temperature: pipe(21, Schema.decodeUnknownSync(Temperature)),
          time: daytime.toJSDate(),
        },
      },
      {
        climateEntityId: trvId,
        scheduledTargetTemperature: pipe(
          18,
          Schema.decodeUnknownSync(Temperature),
        ),
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
        targetTemperature: pipe(23, Schema.decodeUnknownSync(Temperature)),
        climateEntityId: trvId,
      },
      {
        climateEntityId: trvId,
        mode: 'heat',
        targetTemperature: pipe(18.5, Schema.decodeUnknownSync(Temperature)),
        source: 'Device',
      },
      {
        climateEntityId: trvId,
        temperatureReading: {
          temperature: pipe(18.5, Schema.decodeUnknownSync(Temperature)),
          time: daytime.toJSDate(),
        },
      },
      {
        climateEntityId: trvId,
        scheduledTargetTemperature: pipe(
          23,
          Schema.decodeUnknownSync(Temperature),
        ),
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
        targetTemperature: pipe(18.5, Schema.decodeUnknownSync(Temperature)),
        climateEntityId: trvId,
      },
      {
        climateEntityId: trvId,
        mode: 'auto',
        targetTemperature: pipe(23, Schema.decodeUnknownSync(Temperature)),
        source: 'Device',
      },
      {
        climateEntityId: trvId,
        temperatureReading: {
          temperature: pipe(18.5, Schema.decodeUnknownSync(Temperature)),
          time: daytime.toJSDate(),
        },
      },
      {
        climateEntityId: trvId,
        scheduledTargetTemperature: pipe(
          23,
          Schema.decodeUnknownSync(Temperature),
        ),
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
        targetTemperature: pipe(18.5, Schema.decodeUnknownSync(Temperature)),
        climateEntityId: trvId,
      },
      {
        climateEntityId: trvId,
        mode: 'heat',
        targetTemperature: pipe(23, Schema.decodeUnknownSync(Temperature)),
        source: 'Device',
      },
      {
        climateEntityId: trvId,
        temperatureReading: {
          temperature: pipe(18.5, Schema.decodeUnknownSync(Temperature)),
          time: daytime.toJSDate(),
        },
      },
      {
        climateEntityId: trvId,
        scheduledTargetTemperature: pipe(
          23,
          Schema.decodeUnknownSync(Temperature),
        ),
      },
    );

    expect(action).toStrictEqual({
      mode: 'heat',
      targetTemperature: 18.5,
      climateEntityId: trvId,
    });
  });
});
