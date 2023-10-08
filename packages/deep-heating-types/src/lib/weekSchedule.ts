import { DateTime, Duration } from 'luxon';
import {
  HeatingScheduleSlot,
  SimpleWeekSchedule,
  WeekHeatingSchedule,
} from './schedule-types';
import { HeatingSchedule, HeatingScheduleEntry } from './deep-heating-types';
import { ReadonlyRecord, pipe } from 'effect';

function getDaySchedules(
  heatingSchedule: WeekHeatingSchedule
): [string, HeatingScheduleSlot[]][] {
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

function byStart(a: HeatingScheduleEntry, b: HeatingScheduleEntry) {
  return a.start < b.start ? -1 : a.start > b.start ? 1 : 0;
}

export const toHeatingSchedule = (
  schedule: WeekHeatingSchedule,
  now: DateTime
): HeatingSchedule => {
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
        targetTemperature: slot.value.target,
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
};

export const simpleToWeekSchedule = (
  simpleSchedule: SimpleWeekSchedule
): WeekHeatingSchedule =>
  pipe(
    simpleSchedule,
    ReadonlyRecord.map((daySchedule) =>
      pipe(
        daySchedule,
        ReadonlyRecord.collect((time, temperature) => ({
          start: Duration.fromISOTime(time).as('minutes'),
          value: { target: temperature },
        }))
      )
    )
  );
