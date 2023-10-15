import { Schema } from '@effect/schema';
import { DateTime } from 'luxon';
import { SimpleWeekSchedule } from './schedule-types';
import { toHeatingSchedule } from './weekSchedule';

const exampleSchedule = Schema.decodeSync(SimpleWeekSchedule)({
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
        DateTime.local(2023, 10, 16, 9, 30)
      );

      const nowSlot = slots[0];
      expect(nowSlot.start).toEqual(DateTime.local(2023, 10, 16, 9, 24));
      expect(nowSlot.targetTemperature).toEqual(20);

      const nextSlot = slots[1];
      expect(nextSlot.start).toEqual(DateTime.local(2023, 10, 16, 10, 0));
      expect(nextSlot.targetTemperature).toEqual(22);

      const laterSlot = slots[2];
      expect(laterSlot.start).toEqual(DateTime.local(2023, 10, 17, 9, 25));
      expect(laterSlot.targetTemperature).toEqual(21);
    });
  });
});
