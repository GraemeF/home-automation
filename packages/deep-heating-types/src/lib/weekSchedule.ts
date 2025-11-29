import { Array, pipe } from 'effect';
import { DateTime, Duration } from 'luxon';
import { HeatingSchedule, HeatingScheduleEntry } from './deep-heating-types';
import { DaySchedule, WeekSchedule } from './schedule-types';
import { Temperature } from './temperature';

function toStartOfDay(
  day: string,
  startOfDay: DateTime,
  offset: Duration,
  notBeforeTime: DateTime,
): DateTime {
  return startOfDay.toFormat('cccc').toLowerCase() !== day ||
    startOfDay.plus(offset) < notBeforeTime
    ? toStartOfDay(day, startOfDay.plus({ days: 1 }), offset, notBeforeTime)
    : startOfDay.startOf('day');
}

const byStart = (a: HeatingScheduleEntry, b: HeatingScheduleEntry) =>
  a.start.getTime() < b.start.getTime()
    ? -1
    : a.start.getTime() > b.start.getTime()
      ? 1
      : 0;

export const toHeatingSchedule = (
  schedule: WeekSchedule,
  now: DateTime,
): HeatingSchedule => {
  const today = now.startOf('day');
  const futureSlots = (Object.entries(schedule) as [string, DaySchedule][])
    .flatMap(([dayName, slots]) =>
      pipe(
        Object.entries(slots) as [string, Temperature][],
        Array.map(([start, target]) => ({
          start: Duration.fromISOTime(start),
          target,
        })),
        Array.map(({ start, target }) => ({
          start: toStartOfDay(dayName, today, start, now)
            .plus(start)
            .toJSDate(),
          targetTemperature: target,
        })),
      ),
    )
    .sort(byStart);

  const currentSlot = futureSlots[futureSlots.length - 1];
  return [
    {
      start: DateTime.fromJSDate(currentSlot.start)
        .minus({ weeks: 1 })
        .toJSDate(),
      targetTemperature: currentSlot.targetTemperature,
    },
    ...futureSlots,
  ];
};
