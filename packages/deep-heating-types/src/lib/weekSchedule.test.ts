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

  describe('Living Area schedule on Wednesday evening', () => {
    const livingAreaSchedule = decodeWeekSchedule({
      monday: { '07:00': 20, '17:00': 21, '23:45': 15 },
      tuesday: { '07:00': 20, '17:00': 21, '23:45': 15 },
      wednesday: { '07:00': 20, '17:00': 21, '23:45': 15 },
      thursday: { '07:00': 20, '17:00': 21, '23:45': 15 },
      friday: { '07:00': 20, '17:00': 21, '23:45': 15 },
      saturday: { '07:00': 19, '10:00': 21, '17:00': 21, '23:45': 15 },
      sunday: { '07:00': 19, '10:00': 21, '17:00': 21, '23:45': 15 },
    });

    it('at 18:13 should have current target of 21 (active since 17:00)', () => {
      // Wednesday 4th December 2025 at 18:13
      const slots = toHeatingSchedule(
        livingAreaSchedule,
        DateTime.local(2025, 12, 4, 18, 13),
      );

      // The current slot (slots[0]) should be the 17:00 slot with target 21
      const nowSlot = slots[0];
      expect(nowSlot.targetTemperature).toEqual(21);
      // The start should be Wednesday 17:00 (today, since we're past 17:00)
      expect(nowSlot.start).toEqual(
        DateTime.local(2025, 12, 4, 17, 0).toJSDate(),
      );
    });
  });
});
