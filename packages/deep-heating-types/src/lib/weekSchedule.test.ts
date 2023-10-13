import { Schema } from '@effect/schema';
import { Effect, pipe } from 'effect';
import { DateTime } from 'luxon';
import { SimpleWeekSchedule, WeekHeatingSchedule } from './schedule-types';
import { Temperature } from './temperature';
import { simpleToWeekSchedule, toHeatingSchedule } from './weekSchedule';

const exampleSchedule: WeekHeatingSchedule = {
  monday: [
    {
      start: 450,
      value: {
        target: Schema.parseSync(Temperature)(20),
      },
    },
    {
      start: 480,
      value: {
        target: Schema.parseSync(Temperature)(20),
      },
    },
    {
      start: 1020,
      value: {
        target: Schema.parseSync(Temperature)(21),
      },
    },
    {
      start: 1140,
      value: {
        target: Schema.parseSync(Temperature)(21),
      },
    },
    {
      start: 1320,
      value: {
        target: Schema.parseSync(Temperature)(7),
      },
    },
  ],
  tuesday: [
    {
      start: 450,
      value: {
        target: Schema.parseSync(Temperature)(20),
      },
    },
    {
      start: 480,
      value: {
        target: Schema.parseSync(Temperature)(20),
      },
    },
    {
      start: 1020,
      value: {
        target: Schema.parseSync(Temperature)(21),
      },
    },
    {
      start: 1140,
      value: {
        target: Schema.parseSync(Temperature)(21),
      },
    },
    {
      start: 1320,
      value: {
        target: Schema.parseSync(Temperature)(7),
      },
    },
  ],
  wednesday: [
    {
      start: 450,
      value: {
        target: Schema.parseSync(Temperature)(20),
      },
    },
    {
      start: 480,
      value: {
        target: Schema.parseSync(Temperature)(20),
      },
    },
    {
      start: 1020,
      value: {
        target: Schema.parseSync(Temperature)(21),
      },
    },
    {
      start: 1140,
      value: {
        target: Schema.parseSync(Temperature)(21),
      },
    },
    {
      start: 1320,
      value: {
        target: Schema.parseSync(Temperature)(7),
      },
    },
  ],
  thursday: [
    {
      start: 450,
      value: {
        target: Schema.parseSync(Temperature)(20),
      },
    },
    {
      start: 480,
      value: {
        target: Schema.parseSync(Temperature)(20),
      },
    },
    {
      start: 1020,
      value: {
        target: Schema.parseSync(Temperature)(21),
      },
    },
    {
      start: 1140,
      value: {
        target: Schema.parseSync(Temperature)(21),
      },
    },
    {
      start: 1320,
      value: {
        target: Schema.parseSync(Temperature)(7),
      },
    },
  ],
  friday: [
    {
      start: 450,
      value: {
        target: Schema.parseSync(Temperature)(20),
      },
    },
    {
      start: 480,
      value: {
        target: Schema.parseSync(Temperature)(20),
      },
    },
    {
      start: 1020,
      value: {
        target: Schema.parseSync(Temperature)(21),
      },
    },
    {
      start: 1140,
      value: {
        target: Schema.parseSync(Temperature)(21),
      },
    },
    {
      start: 1425,
      value: {
        target: Schema.parseSync(Temperature)(7),
      },
    },
  ],
  saturday: [
    {
      start: 480,
      value: {
        target: Schema.parseSync(Temperature)(20),
      },
    },
    {
      start: 960,
      value: {
        target: Schema.parseSync(Temperature)(20),
      },
    },
    {
      start: 1260,
      value: {
        target: Schema.parseSync(Temperature)(21),
      },
    },
    {
      start: 1425,
      value: {
        target: Schema.parseSync(Temperature)(7),
      },
    },
  ],
  sunday: [
    {
      start: 480,
      value: {
        target: Schema.parseSync(Temperature)(20),
      },
    },
    {
      start: 960,
      value: {
        target: Schema.parseSync(Temperature)(20.5),
      },
    },
    {
      start: 1260,
      value: {
        target: Schema.parseSync(Temperature)(21),
      },
    },
    {
      start: 1320,
      value: {
        target: Schema.parseSync(Temperature)(7),
      },
    },
  ],
};

describe('Hive schedule', () => {
  describe('on Friday morning', () => {
    it('should have correct slots', () => {
      const slots = toHeatingSchedule(
        exampleSchedule,
        DateTime.local(2020, 10, 23, 8, 3)
      );

      const nowSlot = slots[0];
      expect(nowSlot.start).toEqual(DateTime.local(2020, 10, 23, 8, 0));
      expect(nowSlot.targetTemperature).toEqual(20);

      const nextSlot = slots[1];
      expect(nextSlot.start).toEqual(DateTime.local(2020, 10, 23, 17, 0));
      expect(nextSlot.targetTemperature).toEqual(21);
    });
  });

  describe('converting simple to Hive schedule', () => {
    it('should work out minutes', async () => {
      expect(
        await pipe(
          {
            monday: { '09:24': 20, '10:00:00.000': 22 },
            tuesday: { '09:25': 21 },
            wednesday: {},
            thursday: {},
            friday: {},
            saturday: {},
            sunday: {},
          },
          Schema.decode(SimpleWeekSchedule),
          Effect.map(simpleToWeekSchedule),
          Effect.runPromise
        )
      ).toEqual({
        monday: [
          {
            start: 564,
            value: {
              target: Schema.parseSync(Temperature)(20),
            },
          },
          {
            start: 600,
            value: {
              target: Schema.parseSync(Temperature)(22),
            },
          },
        ],
        tuesday: [
          {
            start: 565,
            value: {
              target: Schema.parseSync(Temperature)(21),
            },
          },
        ],
        wednesday: [],
        thursday: [],
        friday: [],
        saturday: [],
        sunday: [],
      });
    });
  });
});
