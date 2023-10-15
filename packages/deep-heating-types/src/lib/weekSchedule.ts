import { ReadonlyArray, ReadonlyRecord, pipe } from 'effect';
import { DateTime, Duration } from 'luxon';
import { HeatingSchedule, HeatingScheduleEntry } from './deep-heating-types';
import { SimpleWeekSchedule } from './schedule-types';

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

const byStart = (a: HeatingScheduleEntry, b: HeatingScheduleEntry) =>
  a.start.toMillis() < b.start.toMillis()
    ? -1
    : a.start.toMillis() > b.start.toMillis()
    ? 1
    : 0;

export const toHeatingSchedule = (
  schedule: SimpleWeekSchedule,
  now: DateTime
): HeatingSchedule => {
  const today = now.startOf('day');
  const futureSlots = ReadonlyRecord.toArray(schedule)
    .flatMap(([dayName, slots]) =>
      pipe(
        slots,
        ReadonlyRecord.toArray,
        ReadonlyArray.map(([start, target]) => ({
          start: Duration.fromISOTime(start),
          target,
        })),
        ReadonlyArray.map(({ start, target }) => ({
          start: toStartOfDay(dayName, today, start, now).plus(start),
          targetTemperature: target,
        }))
      )
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
