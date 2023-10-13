import { Schema } from '@effect/schema';
import {
  ClimateEntityId,
  Temperature,
} from '@home-automation/deep-heating-types';
import { DateTime } from 'luxon';
import { determineAction } from './trvActions';

describe('TRV action', () => {
  const daytime: DateTime = DateTime.fromISO('2020-01-01T12:00Z');
  const trvId = Schema.parseSync(ClimateEntityId)('climate.the_trv');

  it('OFF', () => {
    const action = determineAction(
      {
        climateEntityId: trvId,
        targetTemperature: Schema.parseSync(Temperature)(20),
      },
      {
        climateEntityId: trvId,
        mode: 'OFF',
        source: 'Device',
        targetTemperature: Schema.parseSync(Temperature)(7),
      },
      {
        climateEntityId: trvId,
        temperatureReading: {
          time: daytime.toJSDate(),
          temperature: Schema.parseSync(Temperature)(10),
        },
      },
      {
        climateEntityId: trvId,
        scheduledTargetTemperature: Schema.parseSync(Temperature)(18),
      }
    );

    expect(action).toBeNull();
  });

  it('should do something', () => {
    const action = determineAction(
      {
        targetTemperature: Schema.parseSync(Temperature)(23),
        climateEntityId: trvId,
      },
      {
        climateEntityId: trvId,
        mode: 'MANUAL',
        targetTemperature: Schema.parseSync(Temperature)(18.5),
        source: 'Device',
      },
      {
        climateEntityId: trvId,
        temperatureReading: {
          temperature: Schema.parseSync(Temperature)(21),
          time: daytime.toJSDate(),
        },
      },
      {
        climateEntityId: trvId,
        scheduledTargetTemperature: Schema.parseSync(Temperature)(18),
      }
    );

    expect(action).toStrictEqual({
      mode: 'MANUAL',
      targetTemperature: 23,
      climateEntityId: trvId,
    });
  });

  it('should not change from MANUAL to SCHEDULE', () => {
    const action = determineAction(
      {
        targetTemperature: Schema.parseSync(Temperature)(23),
        climateEntityId: trvId,
      },
      {
        climateEntityId: trvId,
        mode: 'MANUAL',
        targetTemperature: Schema.parseSync(Temperature)(18.5),
        source: 'Device',
      },
      {
        climateEntityId: trvId,
        temperatureReading: {
          temperature: Schema.parseSync(Temperature)(18.5),
          time: daytime.toJSDate(),
        },
      },
      {
        climateEntityId: trvId,
        scheduledTargetTemperature: Schema.parseSync(Temperature)(23),
      }
    );

    expect(action).toStrictEqual({
      mode: 'MANUAL',
      targetTemperature: 23,
      climateEntityId: trvId,
    });
  });

  it('should change from SCHEDULE to MANUAL', () => {
    const action = determineAction(
      {
        targetTemperature: Schema.parseSync(Temperature)(18.5),
        climateEntityId: trvId,
      },
      {
        climateEntityId: trvId,
        mode: 'SCHEDULE',
        targetTemperature: Schema.parseSync(Temperature)(23),
        source: 'Device',
      },
      {
        climateEntityId: trvId,
        temperatureReading: {
          temperature: Schema.parseSync(Temperature)(18.5),
          time: daytime.toJSDate(),
        },
      },
      {
        climateEntityId: trvId,
        scheduledTargetTemperature: Schema.parseSync(Temperature)(23),
      }
    );

    expect(action).toStrictEqual({
      mode: 'MANUAL',
      targetTemperature: 18.5,
      climateEntityId: trvId,
    });
  });

  it('should change MANUAL target temperature', () => {
    const action = determineAction(
      {
        targetTemperature: Schema.parseSync(Temperature)(18.5),
        climateEntityId: trvId,
      },
      {
        climateEntityId: trvId,
        mode: 'MANUAL',
        targetTemperature: Schema.parseSync(Temperature)(23),
        source: 'Device',
      },
      {
        climateEntityId: trvId,
        temperatureReading: {
          temperature: Schema.parseSync(Temperature)(18.5),
          time: daytime.toJSDate(),
        },
      },
      {
        climateEntityId: trvId,
        scheduledTargetTemperature: Schema.parseSync(Temperature)(23),
      }
    );

    expect(action).toStrictEqual({
      mode: 'MANUAL',
      targetTemperature: 18.5,
      climateEntityId: trvId,
    });
  });
});
