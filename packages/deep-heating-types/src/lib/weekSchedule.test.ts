import { describe, expect, it } from 'bun:test';
import { Schema } from 'effect';
import { DateTime } from 'luxon';
import { WeekSchedule } from './schedule-types';
import { toHeatingSchedule } from './weekSchedule';

const decodeWeekSchedule = Schema.decodeSync(WeekSchedule);
const exampleSchedule = decodeWeekSchedule({
  monday: { '09:24': 20, '10:00:00.000': 22 },
  tuesday: { '09:25': 21 },
  wednesday: {},
  thursday: {},
  friday: {},
  saturday: {},
  sunday: {},
});

describe('Weekly schedule', () => {
  describe('on Monday morning', () => {
    it('should have correct slots', () => {
      const slots = toHeatingSchedule(
        exampleSchedule,
        DateTime.local(2023, 10, 16, 9, 30),
      );

      const nowSlot = slots[0];
      expect(nowSlot.start).toEqual(
        DateTime.local(2023, 10, 16, 9, 24).toJSDate(),
      );
      expect(nowSlot.targetTemperature).toEqual(20);

      const nextSlot = slots[1];
      expect(nextSlot.start).toEqual(
        DateTime.local(2023, 10, 16, 10, 0).toJSDate(),
      );
      expect(nextSlot.targetTemperature).toEqual(22);

      const laterSlot = slots[2];
      expect(laterSlot.start).toEqual(
        DateTime.local(2023, 10, 17, 9, 25).toJSDate(),
      );
      expect(laterSlot.targetTemperature).toEqual(21);
    });
  });
});
