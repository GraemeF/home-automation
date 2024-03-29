import { Schema } from '@effect/schema';
import {
  ClimateEntityId,
  Temperature,
} from '@home-automation/deep-heating-types';
import { DateTime } from 'luxon';
import { determineAction } from './trvActions';

describe('TRV action', () => {
  const daytime: DateTime = DateTime.fromISO('2020-01-01T12:00Z');
  const trvId = Schema.decodeUnknownSync(ClimateEntityId)('climate.the_trv');

  it('off', () => {
    const action = determineAction(
      {
        climateEntityId: trvId,
        targetTemperature: Schema.decodeUnknownSync(Temperature)(20),
      },
      {
        climateEntityId: trvId,
        mode: 'off',
        source: 'Device',
        targetTemperature: Schema.decodeUnknownSync(Temperature)(7),
      },
      {
        climateEntityId: trvId,
        temperatureReading: {
          time: daytime.toJSDate(),
          temperature: Schema.decodeUnknownSync(Temperature)(10),
        },
      },
      {
        climateEntityId: trvId,
        scheduledTargetTemperature: Schema.decodeUnknownSync(Temperature)(18),
      },
    );

    expect(action).toBeNull();
  });

  it('should do something', () => {
    const action = determineAction(
      {
        targetTemperature: Schema.decodeUnknownSync(Temperature)(23),
        climateEntityId: trvId,
      },
      {
        climateEntityId: trvId,
        mode: 'heat',
        targetTemperature: Schema.decodeUnknownSync(Temperature)(18.5),
        source: 'Device',
      },
      {
        climateEntityId: trvId,
        temperatureReading: {
          temperature: Schema.decodeUnknownSync(Temperature)(21),
          time: daytime.toJSDate(),
        },
      },
      {
        climateEntityId: trvId,
        scheduledTargetTemperature: Schema.decodeUnknownSync(Temperature)(18),
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
        targetTemperature: Schema.decodeUnknownSync(Temperature)(23),
        climateEntityId: trvId,
      },
      {
        climateEntityId: trvId,
        mode: 'heat',
        targetTemperature: Schema.decodeUnknownSync(Temperature)(18.5),
        source: 'Device',
      },
      {
        climateEntityId: trvId,
        temperatureReading: {
          temperature: Schema.decodeUnknownSync(Temperature)(18.5),
          time: daytime.toJSDate(),
        },
      },
      {
        climateEntityId: trvId,
        scheduledTargetTemperature: Schema.decodeUnknownSync(Temperature)(23),
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
        targetTemperature: Schema.decodeUnknownSync(Temperature)(18.5),
        climateEntityId: trvId,
      },
      {
        climateEntityId: trvId,
        mode: 'auto',
        targetTemperature: Schema.decodeUnknownSync(Temperature)(23),
        source: 'Device',
      },
      {
        climateEntityId: trvId,
        temperatureReading: {
          temperature: Schema.decodeUnknownSync(Temperature)(18.5),
          time: daytime.toJSDate(),
        },
      },
      {
        climateEntityId: trvId,
        scheduledTargetTemperature: Schema.decodeUnknownSync(Temperature)(23),
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
        targetTemperature: Schema.decodeUnknownSync(Temperature)(18.5),
        climateEntityId: trvId,
      },
      {
        climateEntityId: trvId,
        mode: 'heat',
        targetTemperature: Schema.decodeUnknownSync(Temperature)(23),
        source: 'Device',
      },
      {
        climateEntityId: trvId,
        temperatureReading: {
          temperature: Schema.decodeUnknownSync(Temperature)(18.5),
          time: daytime.toJSDate(),
        },
      },
      {
        climateEntityId: trvId,
        scheduledTargetTemperature: Schema.decodeUnknownSync(Temperature)(23),
      },
    );

    expect(action).toStrictEqual({
      mode: 'heat',
      targetTemperature: 18.5,
      climateEntityId: trvId,
    });
  });
});
