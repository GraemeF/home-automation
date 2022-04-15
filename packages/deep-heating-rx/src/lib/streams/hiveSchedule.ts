import { DateTime, Duration } from 'luxon';
import {
  HiveHeatingSchedule,
  HiveHeatingScheduleSlot,
} from '@home-automation/deep-heating-hive';
import { HeatingSchedule } from '@home-automation/deep-heating-types';

function getDaySchedules(
  heatingSchedule: HiveHeatingSchedule
): [string, HiveHeatingScheduleSlot[]][] {
  return Object.entries(heatingSchedule).map(([day, value]) => [day, value]);
}

function toStartOfDay(
  day: string,
  startOfDay: DateTime,
  offset: Duration,
  notBeforeTime: DateTime
): DateTime {
  return startOfDay.toFormat('cccc').toLowerCase() !== day ||
    startOfDay.plus(offset) < notBeforeTime
    ? toStartOfDay(day, startOfDay.plus({ days: 1 }), offset, notBeforeTime)
    : startOfDay.startOf('day');
}

interface HeatingScheduleSlot {
  start: DateTime;
  targetTemperature: number;
}

function byStart(a: HeatingScheduleSlot, b: HeatingScheduleSlot) {
  return a.start < b.start ? -1 : a.start > b.start ? 1 : 0;
}

export function toHeatingSchedule(
  schedule: HiveHeatingSchedule,
  now: DateTime
): HeatingSchedule {
  const today = now.startOf('day');
  const futureSlots = getDaySchedules(schedule)
    .flatMap(([dayName, slots]) =>
      slots.map((slot) => ({
        start: toStartOfDay(
          dayName,
          today,
          Duration.fromObject({ minutes: slot.start }),
          now
        ).plus({ minutes: slot.start }),
        targetTemperature: slot.value.heat ?? slot.value.target,
      }))
    )
    .sort(byStart);

  const currentSlot = futureSlots[futureSlots.length - 1];
  return [
    {
      start: currentSlot.start.minus({ weeks: 1 }),
      targetTemperature: currentSlot.targetTemperature,
    },
    ...futureSlots,
  ];
}
