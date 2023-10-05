import { DateTime } from 'luxon';
import { toHeatingSchedule } from './weekSchedule';
import { WeekHeatingSchedule } from './schedule-types';

const exampleSchedule: WeekHeatingSchedule = {
  monday: [
    {
      start: 450,
      value: {
        target: 20,
      },
    },
    {
      start: 480,
      value: {
        target: 20,
      },
    },
    {
      start: 1020,
      value: {
        target: 21,
      },
    },
    {
      start: 1140,
      value: {
        target: 21,
      },
    },
    {
      start: 1320,
      value: {
        target: 7,
      },
    },
  ],
  tuesday: [
    {
      start: 450,
      value: {
        target: 20,
      },
    },
    {
      start: 480,
      value: {
        target: 20,
      },
    },
    {
      start: 1020,
      value: {
        target: 21,
      },
    },
    {
      start: 1140,
      value: {
        target: 21,
      },
    },
    {
      start: 1320,
      value: {
        target: 7,
      },
    },
  ],
  wednesday: [
    {
      start: 450,
      value: {
        target: 20,
      },
    },
    {
      start: 480,
      value: {
        target: 20,
      },
    },
    {
      start: 1020,
      value: {
        target: 21,
      },
    },
    {
      start: 1140,
      value: {
        target: 21,
      },
    },
    {
      start: 1320,
      value: {
        target: 7,
      },
    },
  ],
  thursday: [
    {
      start: 450,
      value: {
        target: 20,
      },
    },
    {
      start: 480,
      value: {
        target: 20,
      },
    },
    {
      start: 1020,
      value: {
        target: 21,
      },
    },
    {
      start: 1140,
      value: {
        target: 21,
      },
    },
    {
      start: 1320,
      value: {
        target: 7,
      },
    },
  ],
  friday: [
    {
      start: 450,
      value: {
        target: 20,
      },
    },
    {
      start: 480,
      value: {
        target: 20,
      },
    },
    {
      start: 1020,
      value: {
        target: 21,
      },
    },
    {
      start: 1140,
      value: {
        target: 21,
      },
    },
    {
      start: 1425,
      value: {
        target: 7,
      },
    },
  ],
  saturday: [
    {
      start: 480,
      value: {
        target: 20,
      },
    },
    {
      start: 960,
      value: {
        target: 20,
      },
    },
    {
      start: 1260,
      value: {
        target: 21,
      },
    },
    {
      start: 1425,
      value: {
        target: 7,
      },
    },
  ],
  sunday: [
    {
      start: 480,
      value: {
        target: 20,
      },
    },
    {
      start: 960,
      value: {
        target: 20.5,
      },
    },
    {
      start: 1260,
      value: {
        target: 21,
      },
    },
    {
      start: 1320,
      value: {
        target: 7,
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
});
